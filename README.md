# anaPhotoPipeline

Matlab code for photometry analysis for the Jones Lab, descigned for analyzing the NAc Kappa data set.

anaPhotoData_nacKap.m - The code that runs/manages each of the subroutines. Should be the only piece of code that needs to be modifed to analyze the data. The variables are described in the code. 

code/
    Subroutines are located in this folder that carryout the analysis. It is not recommended that changes are made to these routines. 

data/
    Put the curated data in this folder as well as the metaData.mat file. 

res/ 
    Results will be saved to this folder. Figures (.pdf) and data to make figures (.mat). 
