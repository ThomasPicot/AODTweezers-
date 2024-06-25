# AODTweezers-

# installation
This code comes from this repository: https://github.com/JQIamo/AWG-on-GPU All the information about installing the drivers can be found on their repository. I would like to add two things: 
- You need a RDMA compatible NVIDIA GPU to make the code run. It is related to QUADRO familly (not RTX).
- The SCAPP is an option that you have to buy directly from spectrum instruments company (around 300€). 


Finally this code has been maid for this paper: https://arxiv.org/abs/2403.15582
# implementation 

The idea is to interface their code and to implement our functions to make it work with our system. In our case we want two main things:
 - First, we want to turn on the power of the tweezers with a ramp, so it will change the StaticWaveGeneration_single() function in "cuda_functions.cu" file.
 - We also want to move the tweezers but with more steps than just from point A to point B. The idea is to have a 1D register, and to move each tweezer from their initial position to an upper position for a certain time, and then to put it back to its initial position.

 - in the end we want to implement de trigger mode.
