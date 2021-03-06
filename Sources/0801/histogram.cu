#include <stdio.h>
#include <stdint.h>
#include <assert.h>

#include <cuda_runtime.h>

#include <helper_functions.h>
#include <helper_cuda.h>

#define MAX_BINS 4096
#define MAX_BINS_SIZE 256




/*****************************/
/*    printData is used for
/*    printing the generated data   
/*****************************/
void printData(unsigned int *data, unsigned int dataSize)
{
    printf("Data generated : [");
    for (int a = 0; a < dataSize; a++)
    {
        printf("%d", data[a]);
        if (a == dataSize - 1)
        {
            printf("]\n");
        }
        if (a != dataSize - 1)
        {
            printf("-");
        }
    }
}


/*****************************/
/*    histogram is the main kernel
/*    used to calculate the histogram generated   
/*****************************/
__global__ static void histogram(unsigned int *input, unsigned int *histo, unsigned int dataSize, unsigned int binSize)
{
    int th = blockIdx.x * blockDim.x + threadIdx.x;
    extern __shared__ int sharedHist[];
    for (int i = threadIdx.x; i < binSize; i += blockDim.x)
    {
        sharedHist[i] = 0;
    }
    __syncthreads();
    
    for (int counterFill = th; counterFill < dataSize; counterFill += blockDim.x * gridDim.x)
    {
        //if(input[counterFill] < MAX_BINS_SIZE){
            atomicAdd(&sharedHist[input[counterFill]], 1);
        //}

    }
    __syncthreads();
    

    for (int j = threadIdx.x; j < binSize; j += blockDim.x)
    {
        atomicAdd(&histo[j], sharedHist[j]);
    }

}

/*****************************/
/*    compareHistograms is used for
/*    comparing the performance of the 2 methods single and multi thread    
/*****************************/
bool compareHistograms(unsigned int *firstTab, unsigned int *secondTab, int tabSize)
{
    for(int i = 0; i<tabSize; i++)
    {
        if (firstTab[i] != secondTab[i])
        {
            return false;
        }
    }
    return true;
}

/*****************************/
/*    printResult is used for
/*    printing the results   
/*****************************/
void printResult(unsigned int *res, int threadNb, unsigned int Size )
{
    printf("Result for %d threads: [", threadNb);
    for (int i = 0; i < Size; i++)
    {
        printf("%d", res[i]);
        if (i != Size - 1){
            printf("|");
        }

        if (i == Size - 1){
            printf("]\n");
        }
    }
}

/*****************************/
/*    cleanHisto when finish (all the columns to 0)    
/*****************************/
__global__ static void cleanHisto(unsigned int *histo, unsigned int binSize)
{
    for (int i = threadIdx.x; i < binSize; i += blockDim.x)
    {
        histo[i] = 0;
    }
    __syncthreads();

}

void wrapper(unsigned int dataSize, unsigned int binSize, int showData, int threadNb, int blockCount)
{

    unsigned int *histo = NULL;
    unsigned int *histo_single = NULL;
    unsigned int *device_histo = NULL;
    unsigned int *data = NULL;
    unsigned int *device_data = NULL;


    data = (unsigned int *)malloc(dataSize * sizeof(unsigned int));
    histo = (unsigned int *)malloc(binSize * sizeof(unsigned int));
    histo_single = (unsigned int *)malloc(binSize * sizeof(unsigned int));


    //generating some data
    srand(time(NULL));
    for (int i = 0; i < dataSize; i++){
        data[i] = rand() % binSize;
    }
    printf("Done\n");

    //showing the data if the user wants to see it
    if (showData == 1)
    {
        printData(data, dataSize);
    }

    checkCudaErrors(cudaMalloc((void **)&device_histo, sizeof(unsigned int) * binSize));
    checkCudaErrors(cudaMalloc((void **)&device_data, sizeof(unsigned int) * dataSize));

    checkCudaErrors(cudaMemcpy(device_data, data, sizeof(unsigned int) * dataSize, cudaMemcpyHostToDevice));

    //event init
    cudaEvent_t mulTStart;
    cudaEvent_t singTStart;
    cudaEvent_t mulTStop;
    cudaEvent_t singTStop;
    checkCudaErrors(cudaEventCreate(&mulTStart));
    checkCudaErrors(cudaEventCreate(&mulTStop));
    checkCudaErrors(cudaEventRecord(mulTStart, NULL));

    //lauching the kernel with multiple thread
    histogram<<<blockCount, threadNb,sizeof(unsigned int) * binSize>>>(device_data, device_histo, dataSize, binSize);
    cudaDeviceSynchronize();

    printf("End of the kernel, fetching the results :\n");
    checkCudaErrors(cudaMemcpy(histo, device_histo, sizeof(unsigned int) * binSize, cudaMemcpyDeviceToHost));

    //creatiion of events for time measuring
    checkCudaErrors(cudaEventRecord(mulTStop, NULL));
    checkCudaErrors(cudaEventSynchronize(mulTStop));

    checkCudaErrors(cudaEventCreate(&singTStart));
    checkCudaErrors(cudaEventCreate(&singTStop));
    checkCudaErrors(cudaEventRecord(singTStart, NULL));

    //cleaning the histogram
    cleanHisto<<<1, threadNb>>>(device_histo, binSize);
    cudaDeviceSynchronize();

    //lauching the kernel for a single thread for comparaison
    histogram<<<1, 1,sizeof(unsigned int) * binSize>>>(device_data, device_histo, dataSize, binSize);
    cudaDeviceSynchronize();

    checkCudaErrors(cudaMemcpy(histo_single, device_histo, sizeof(unsigned int) * binSize, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaEventRecord(singTStop, NULL));
    checkCudaErrors(cudaEventSynchronize(singTStop));
    float msecTotal = 0.0f;
    float msecTotal_single = 0.0f;
    checkCudaErrors(cudaEventElapsedTime(&msecTotal, mulTStart, mulTStop));
    checkCudaErrors(cudaEventElapsedTime(&msecTotal_single, singTStart, singTStop));
    double gigaFlops = (dataSize * 1.0e-9f) / (msecTotal / 1000.0f);
    double gigaFlops_single = (dataSize * 1.0e-9f) / (msecTotal_single / 1000.0f);

    // Print the histograms if the parameter
    if (showData == 1)
    {
        printResult(histo, threadNb, binSize);
        printResult(histo_single, 1, binSize);
    }

    // compareHistograms the results of the two histograms
    if (compareHistograms(histo, histo_single, binSize))
    {
        printf("histograms matched");
    }
    else
    {
        printf("Something went wrong the histograms doesn't matched !!");
    }
    // Print performances
    printf("%d threads :\nCuda processing time = %.3fms, \n Perf = %.3f Gflops\n",threadNb, msecTotal, gigaFlops);
    printf("1 thread :\nCuda processing time = %.3fms, \n Perf = %.3f Gflops\n", msecTotal_single, gigaFlops_single);
    checkCudaErrors(cudaFree(device_data));
    checkCudaErrors(cudaFree(device_histo));
    free(histo);
    free(histo_single);
    free(data);

}

int main(int argc, char **argv)
{
    int print = 0;
    unsigned int binSize = MAX_BINS;
    unsigned long long input_dataSize = 0;

    char *dataSize = NULL;
    cudaDeviceProp cudaprop;
    int smCount;

    // retrieve device
    int dev = findCudaDevice(argc, (const char **)argv);
    cudaGetDeviceProperties(&cudaprop, dev);

    smCount = cudaprop.multiProcessorCount;
    
    //Retrieving parameters
    if (checkCmdLineFlag(argc, (const char **)argv, "size"))
    {
        getCmdLineArgumentString(argc, (const char **)argv, "size", &dataSize);
        input_dataSize = atoll(dataSize);
    }
    if (checkCmdLineFlag(argc, (const char **)argv, "displayData"))
    {
        print = 1;
    }

    printf("Data Size is: %d \n", input_dataSize);
    //Max is 2^32 as asked
    if (input_dataSize >= 4294967296 || input_dataSize == 0) {
        printf("Error: Data size > 4,294,967,296");
        exit(EXIT_FAILURE);
    }


    int nbThread = min((int)input_dataSize, 1024);
    printf("nb thread: %d \n", nbThread);
    //my number of block depends of the input because if the nb of thread is <1024 there will be only one blocks, in contrary if it is
    // > 1024 then the number of blocks will depend of the input with the maximum size of 18000
    int nbBlock =  min(((int)input_dataSize/nbThread),100*smCount);

    if (nbBlock == 0) nbBlock = 1;
    printf("nbblock: %d \n", nbBlock);
    wrapper(input_dataSize, binSize, print, nbThread, nbBlock);
    return EXIT_SUCCESS;
}