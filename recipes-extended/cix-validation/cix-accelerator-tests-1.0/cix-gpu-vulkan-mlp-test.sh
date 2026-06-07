#!/usr/bin/env bash
set -euo pipefail
OUTDIR="${1:-$HOME/proof-$(date +%Y%m%d)/gpu-vulkan-mlp}"
mkdir -p "$OUTDIR"
cd "$OUTDIR"
cat > mlp.comp <<'SHADER'
#version 450
layout(local_size_x = 1) in;
layout(std430, binding = 0) readonly buffer InBuf { float x[4]; } inb;
layout(std430, binding = 1) writeonly buffer OutBuf { float y[3]; } outb;
void main() {
    float h0 = max(0.0, 0.50*inb.x[0] + -0.25*inb.x[1] + 0.75*inb.x[2] + 0.10*inb.x[3] + 0.10);
    float h1 = max(0.0, -0.30*inb.x[0] + 0.80*inb.x[1] + 0.20*inb.x[2] + -0.60*inb.x[3] + 0.20);
    float h2 = max(0.0, 0.90*inb.x[0] + 0.10*inb.x[1] + -0.40*inb.x[2] + 0.30*inb.x[3] - 0.10);
    outb.y[0] = 1.20*h0 + -0.70*h1 + 0.30*h2 + 0.01;
    outb.y[1] = -0.40*h0 + 1.10*h1 + -0.20*h2 - 0.02;
    outb.y[2] = 0.10*h0 + 0.20*h1 + 1.30*h2 + 0.03;
}
SHADER
glslc mlp.comp -o mlp.spv
cat > gpu_mlp_vulkan.c <<'C'
#include <vulkan/vulkan.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#define VK_CHECK(x) do { VkResult err=(x); if(err){fprintf(stderr,"VK error %d at %s:%d\n",err,__FILE__,__LINE__); return 2;} } while(0)
static char* read_file(const char* path, size_t* size){ FILE* f=fopen(path,"rb"); if(!f){perror(path); exit(2);} fseek(f,0,SEEK_END); long n=ftell(f); rewind(f); char* b=malloc(n); fread(b,1,n,f); fclose(f); *size=n; return b; }
static uint32_t find_mem(VkPhysicalDevice phy, uint32_t bits, VkMemoryPropertyFlags flags){ VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(phy,&mp); for(uint32_t i=0;i<mp.memoryTypeCount;i++) if((bits&(1u<<i)) && (mp.memoryTypes[i].propertyFlags&flags)==flags) return i; fprintf(stderr,"no memory type\n"); exit(2); }
int main(){
 VkApplicationInfo app={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.pApplicationName="cix-gpu-mlp-infer",.apiVersion=VK_API_VERSION_1_1};
 VkInstanceCreateInfo ici={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&app}; VkInstance inst; VK_CHECK(vkCreateInstance(&ici,NULL,&inst));
 uint32_t n=0; vkEnumeratePhysicalDevices(inst,&n,NULL); if(!n){fprintf(stderr,"no physical devices\n"); return 2;} VkPhysicalDevice phys[8]; if(n>8)n=8; vkEnumeratePhysicalDevices(inst,&n,phys);
 VkPhysicalDevice phy=VK_NULL_HANDLE; VkPhysicalDeviceProperties props; for(uint32_t i=0;i<n;i++){ vkGetPhysicalDeviceProperties(phys[i],&props); if(props.deviceType != VK_PHYSICAL_DEVICE_TYPE_CPU){ phy=phys[i]; break; }} if(!phy){fprintf(stderr,"no non-CPU Vulkan GPU\n"); return 2;} vkGetPhysicalDeviceProperties(phy,&props); printf("GPU_DEVICE=%s vendor=0x%04x device=0x%08x driver=%u\n",props.deviceName,props.vendorID,props.deviceID,props.driverVersion);
 uint32_t qn=0; vkGetPhysicalDeviceQueueFamilyProperties(phy,&qn,NULL); VkQueueFamilyProperties qps[16]; vkGetPhysicalDeviceQueueFamilyProperties(phy,&qn,qps); uint32_t q=UINT32_MAX; for(uint32_t i=0;i<qn;i++) if(qps[i].queueFlags & VK_QUEUE_COMPUTE_BIT){q=i;break;} if(q==UINT32_MAX){fprintf(stderr,"no compute queue\n");return 2;}
 float prio=1.0f; VkDeviceQueueCreateInfo qci={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,.queueFamilyIndex=q,.queueCount=1,.pQueuePriorities=&prio}; VkDeviceCreateInfo dci={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.queueCreateInfoCount=1,.pQueueCreateInfos=&qci}; VkDevice dev; VK_CHECK(vkCreateDevice(phy,&dci,NULL,&dev)); VkQueue queue; vkGetDeviceQueue(dev,q,0,&queue);
 float in[4]={1.0f,2.0f,-1.0f,0.5f}; float expected[3]; float h0=fmaxf(0,0.5f*in[0]-0.25f*in[1]+0.75f*in[2]+0.10f*in[3]+0.10f); float h1=fmaxf(0,-0.30f*in[0]+0.80f*in[1]+0.20f*in[2]-0.60f*in[3]+0.20f); float h2=fmaxf(0,0.90f*in[0]+0.10f*in[1]-0.40f*in[2]+0.30f*in[3]-0.10f); expected[0]=1.20f*h0-0.70f*h1+0.30f*h2+0.01f; expected[1]=-0.40f*h0+1.10f*h1-0.20f*h2-0.02f; expected[2]=0.10f*h0+0.20f*h1+1.30f*h2+0.03f;
 VkBuffer bufs[2]; VkDeviceMemory mems[2]; VkDeviceSize sizes[2]={sizeof(in),sizeof(expected)}; for(int i=0;i<2;i++){ VkBufferCreateInfo bci={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,.size=sizes[i],.usage=VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,.sharingMode=VK_SHARING_MODE_EXCLUSIVE}; VK_CHECK(vkCreateBuffer(dev,&bci,NULL,&bufs[i])); VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev,bufs[i],&mr); VkMemoryAllocateInfo mai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=mr.size,.memoryTypeIndex=find_mem(phy,mr.memoryTypeBits,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)}; VK_CHECK(vkAllocateMemory(dev,&mai,NULL,&mems[i])); VK_CHECK(vkBindBufferMemory(dev,bufs[i],mems[i],0)); }
 void* p; vkMapMemory(dev,mems[0],0,sizeof(in),0,&p); memcpy(p,in,sizeof(in)); vkUnmapMemory(dev,mems[0]);
 VkDescriptorSetLayoutBinding bs[2]={{.binding=0,.descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,.descriptorCount=1,.stageFlags=VK_SHADER_STAGE_COMPUTE_BIT},{.binding=1,.descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,.descriptorCount=1,.stageFlags=VK_SHADER_STAGE_COMPUTE_BIT}}; VkDescriptorSetLayoutCreateInfo slci={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,.bindingCount=2,.pBindings=bs}; VkDescriptorSetLayout sl; VK_CHECK(vkCreateDescriptorSetLayout(dev,&slci,NULL,&sl)); VkPipelineLayoutCreateInfo plci={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,.setLayoutCount=1,.pSetLayouts=&sl}; VkPipelineLayout pl; VK_CHECK(vkCreatePipelineLayout(dev,&plci,NULL,&pl));
 size_t spvsz; char* spv=read_file("mlp.spv",&spvsz); VkShaderModuleCreateInfo smci={.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,.codeSize=spvsz,.pCode=(uint32_t*)spv}; VkShaderModule sm; VK_CHECK(vkCreateShaderModule(dev,&smci,NULL,&sm)); VkComputePipelineCreateInfo cpci={.sType=VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,.stage={.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_COMPUTE_BIT,.module=sm,.pName="main"},.layout=pl}; VkPipeline pipe; VK_CHECK(vkCreateComputePipelines(dev,VK_NULL_HANDLE,1,&cpci,NULL,&pipe));
 VkDescriptorPoolSize ps={.type=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,.descriptorCount=2}; VkDescriptorPoolCreateInfo dpci={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,.maxSets=1,.poolSizeCount=1,.pPoolSizes=&ps}; VkDescriptorPool dp; VK_CHECK(vkCreateDescriptorPool(dev,&dpci,NULL,&dp)); VkDescriptorSetAllocateInfo dsai={.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,.descriptorPool=dp,.descriptorSetCount=1,.pSetLayouts=&sl}; VkDescriptorSet ds; VK_CHECK(vkAllocateDescriptorSets(dev,&dsai,&ds)); VkDescriptorBufferInfo bi[2]={{.buffer=bufs[0],.offset=0,.range=sizeof(in)},{.buffer=bufs[1],.offset=0,.range=sizeof(expected)}}; VkWriteDescriptorSet wr[2]={{.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds,.dstBinding=0,.descriptorCount=1,.descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,.pBufferInfo=&bi[0]},{.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,.dstSet=ds,.dstBinding=1,.descriptorCount=1,.descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,.pBufferInfo=&bi[1]}}; vkUpdateDescriptorSets(dev,2,wr,0,NULL);
 VkCommandPoolCreateInfo cpooli={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,.queueFamilyIndex=q}; VkCommandPool cpool; VK_CHECK(vkCreateCommandPool(dev,&cpooli,NULL,&cpool)); VkCommandBufferAllocateInfo cbai={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,.commandPool=cpool,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1}; VkCommandBuffer cb; VK_CHECK(vkAllocateCommandBuffers(dev,&cbai,&cb)); VkCommandBufferBeginInfo cbi={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO}; VK_CHECK(vkBeginCommandBuffer(cb,&cbi)); vkCmdBindPipeline(cb,VK_PIPELINE_BIND_POINT_COMPUTE,pipe); vkCmdBindDescriptorSets(cb,VK_PIPELINE_BIND_POINT_COMPUTE,pl,0,1,&ds,0,NULL); vkCmdDispatch(cb,1,1,1); VK_CHECK(vkEndCommandBuffer(cb)); VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cb}; VK_CHECK(vkQueueSubmit(queue,1,&si,VK_NULL_HANDLE)); VK_CHECK(vkQueueWaitIdle(queue));
 float out[3]; vkMapMemory(dev,mems[1],0,sizeof(out),0,&p); memcpy(out,p,sizeof(out)); vkUnmapMemory(dev,mems[1]); printf("GPU_MLP_OUTPUT=%.6f %.6f %.6f\n",out[0],out[1],out[2]); printf("CPU_EXPECTED=%.6f %.6f %.6f\n",expected[0],expected[1],expected[2]); float maxerr=0; for(int i=0;i<3;i++){ float e=fabsf(out[i]-expected[i]); if(e>maxerr) maxerr=e; } int cls=0; if(out[1]>out[cls])cls=1; if(out[2]>out[cls])cls=2; printf("GPU_INFERENCE_CLASS=%d MAX_ABS_ERR=%g\n",cls,maxerr); return maxerr < 1e-5f ? 0 : 3; }
C
${CC:-gcc} gpu_mlp_vulkan.c -o gpu_mlp_vulkan -lvulkan -lm
MESA_LOADER_DRIVER_OVERRIDE=panthor ./gpu_mlp_vulkan 2>&1 | tee gpu_mlp_vulkan.log
sha256sum gpu_mlp_vulkan mlp.spv gpu_mlp_vulkan.log | tee gpu_mlp_sha256.txt
