
<!-- README.md is generated from README.Rmd. Please edit that file -->
FLAME (Fast, Large-scale, Almost Matching Exactly)
--------------------------------------------------

### Overview of the FLAME algorithm

The **FLAME** algorithm provides fast and large-scale matching approach to causal inference. **FLAME** creates matches that include as many covariates as possible, and iteratively drops covariates that are successively less useful for predicting outcomes based on matching quality. Currently the `FLAME` package applies to categorical data, and provides two approaches for implementation - bit vectors and database management systems (e.g., PostgreSQL, SQLite). For data that has been preprocessed and fits in memory, bit vectors should be applied. For extremely large data that does not fit in memory, database systems should be applied.

For more details about the FLAME algorithm, please refer to the paper: [FLAME: A Fast Large-scale Almost Matching Exactly Approach to Causal Inference](https://arxiv.org/pdf/1707.06315.pdf)

### Required data format

`FLAME` package requires input data to have specific format. First, input data should be a **R Data Frame**. Second, all covariates in the input data should be categorical covariates, represented by *factor* R data type. If there are continuous covariates, please consider regrouping. Third, input data columns should contain (1) covariates, (2) outcome variable in *numeric* R data type, and (3) variable specifying a unit is treated or control (treated = 1, control = 0) in *factor* R data type. Lastly, though there are no requirements for input data column names, the column order should follow *\[covariates, outcome, treated\]*. Below is an example of input data with *n* units and *m* covariates.

|                 | ***x*<sub>1</sub>** | ***x*<sub>2</sub>** |  **...** | ***x*<sub>*m* − 1</sub>** | ***x*<sub>*m*</sub>** | **outcome** | **treated** |
|:---------------:|:-------------------:|:-------------------:|:--------:|:-------------------------:|:---------------------:|:-----------:|:-----------:|
| **R data type** |       *factor*      |       *factor*      | *factor* |          *factor*         |        *factor*       |  *numeric*  |   *factor*  |
|    **unit 1**   |          0          |          1          |    ...   |             1             |           2           |     3.8     |      1      |
|    **unit 2**   |          1          |          0          |    ...   |             1             |           0           |     1.36    |      0      |
|    **unit 3**   |          0          |          1          |    ...   |             0             |           1           |    -7.25    |      0      |
|       ...       |         ...         |         ...         |    ...   |            ...            |          ...          |     ...     |     ...     |
|   **unit *n***  |          0          |          1          |    ...   |             1             |           0           |      20     |      1      |

Holdout training data should also follow the same format.

### Other requirements

1.  `FLAME` requires installation of python, specifically with at least python3 version. If your computer system does not have python3, install from [here](https://www.python.org/downloads/).

2.  For database systems implementation, please name the database connection as **db**.

### Installation

``` r
# Current version on GitHub
devtools::install_github("chiarui424/FLAME") 
```

### Some examples

[Apply the FLAME Algorithm to Synthetic Data](articles/Synthetic_Data.html)
[Get Detailed Information After Matching](articles/CATE.html)
[Matching Quality](articles/Matching_Quality.html)