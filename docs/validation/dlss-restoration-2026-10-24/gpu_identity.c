#include <vulkan/vulkan.h>
#include <stdio.h>
int main(void) {
 VkApplicationInfo app={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.pApplicationName="DLSS test identity",.apiVersion=VK_API_VERSION_1_1};
 VkInstanceCreateInfo ci={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&app};
 VkInstance instance; if(vkCreateInstance(&ci,NULL,&instance)!=VK_SUCCESS)return 1;
 uint32_t count=8; VkPhysicalDevice devices[8]; if(vkEnumeratePhysicalDevices(instance,&count,devices)!=VK_SUCCESS)return 2;
 for(uint32_t i=0;i<count;i++) {
  VkPhysicalDeviceIDProperties id={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES};
  VkPhysicalDeviceProperties2 p={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,.pNext=&id};
  vkGetPhysicalDeviceProperties2(devices[i],&p);
  printf("%s|%04x|%04x|",p.properties.deviceName,p.properties.vendorID,p.properties.deviceID);
  for(int j=0;j<16;j++) printf("%02x",id.deviceUUID[j]);puts("");
 }
 vkDestroyInstance(instance,NULL);return 0;
}
