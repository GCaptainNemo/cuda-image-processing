# CUDA-Image-processing

## 一、介绍

本仓库用CUDA编程实现图像处理的算法。相比于串行的方式，使用GPU调用多线程完成速度要快得多。

## 二、安装方法 

## 2.1 CUDA C++

```
cd cuda-conv
mkdir build
cd build
cmake ..
```

## 2.2 PyCUDA python

```
cd cuda-conv
cd pycuda
python xxx.py
```



## 三、已实现功能

1. 图像2D卷积(`namespace conv`)
2. 图像Harris角点提取(`namespace harris`)
3. 构造高斯图像金字塔(`namespace gau_pyr`)   
4. 构造高斯差分(DoG)金字塔(`namespace gau_pyr`)
5. 灰度图像形态学操作(腐蚀、膨胀)(`namespace morphology`)
6. 提取图像边缘，逆距离变换 PyCUDA
