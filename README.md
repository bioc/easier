# easier <img src="vignettes/easier_logo.png" alt="EaSIeR logo" width="70" height="70" align="right">
---
 
<!-- badges: start -->
[![R-CMD-check](https://github.com/olapuentesantana/easier_devel/workflows/R-CMD-check/badge.svg)](https://github.com/olapuentesantana/easier_devel/actions)
<!-- badges: end -->

## Description

The goal of `easier` is to contextualize the prediction of anti-tumor immune responses from RNA-seq data using EaSIeR. 

EaSIeR is a tool to predict biomarker-based immunotherapy based on cancer-specific models of immune response. Model biomarkers have been experimentally validated in the literature and the performance of EaSIeR predictions has been validated using independent datasets from four different cancer types with patients treated with anti-PD1 or anti-PD-L1 therapy.

These models are available through `easierData` package and can be accessed using `get_opt_models()`.

Please see [Lapuente-Santana O et al., Patterns, 2021,](https://doi.org/10.1016/j.patter.2021.100293) for additional details on EaSIeR.

<img src="vignettes/easier_image.png" width="550" alt="EaSIeR approach">

## Installation

You can install `easier` package from bioconductor with:

``` r
if (!requireNamespace("BiocManager", quietly = TRUE))
    install.packages("BiocManager")

BiocManager::install("easier")
          
```

Additionally, you can install the development version from the GitHub repository:

``` r
library("remotes")
remotes::install_github("olapuentesantana/easier", 
                        dependencies = TRUE, build_vignettes = TRUE)
```
## Example

A more detailed pipeline is available in the vignette:
``` r
vignette("easier_user_manual", package = "easier")
```
## Citation

If you use this package in your work, please cite the original EaSIeR study:

Lapuente-Santana, Ó., van Genderen, M., Hilbers, P., Finotello, F., & Eduati, F. (2021). 'Interpretable systems biomarkers predict response to immune-checkpoint inhibitors.' Patterns (New York, N.Y.), 2(8), 100293. https://doi.org/10.1016/j.patter.2021.100293
