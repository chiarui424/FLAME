aggregate_table <- function(list) {
  tab = table(as.character(list))
  tab = unclass(tab)
  name = names(tab)
  list_val = as.character(list)
  return(as.vector(tab[sapply(list_val, function(x) which(name ==  x))]))
}

# update_matched_bit takes a dataframe, a set of covariates to match on,
# the treatment indicator column and the matched indicator column.
# it returns the array indicating whether each unit is matched (the first return value),
# and a list of indices for the matched units (the second return value)

update_matched_bit <- function(data, cur_covs, covs_max_list, compute_var) {

  data_wo_t = as.bigz(as.matrix(data[,cur_covs+1])) # the covariates values as a matrix

  options("scipen"=100, "digits"=4)

  # Compute b_u
  multiplier = as.bigz(rep(0,length(cur_covs)))
  for (i in 1:length(cur_covs)) {
    multiplier[i] = pow.bigz(covs_max_list[i],i-1)
  }
  b_u = as.vector(data_wo_t %*% as.matrix(multiplier))

  # Compute b_u+
  multiplier = as.bigz(rep(0,length(cur_covs)))
  for (i in 1:length(cur_covs)) {
    multiplier[i] = pow.bigz(covs_max_list[i],i)
  }

  b_u_plus = as.vector(data_wo_t %*% as.matrix(multiplier))
  b_u_plus = add.bigz(b_u_plus, data[,'treated'])

  # Compute c_u
  c_u = aggregate_table(b_u)

  # Compute c_u+
  c_u_plus = aggregate_table(b_u_plus)

  if (compute_var) {
    match_index = mapply(function(x,y) (x != y) && (x >= 4) && (y >= 2) && (x - y >= 2), c_u, c_u_plus)
  }
  else {
    match_index = mapply(function(x,y) (x != y) && (x >= 2) && (y >= 1), c_u, c_u_plus)
  }
  index = b_u[match_index]
  return(list(match_index, index))
}

#get_CATE function takes match_index and index (b_u values)
# and return dataframe that includes
#(1) list of covariates that are used to match at level l
#(1) conditional average treatment effect (effect)
#(2) size of each matched group (size)

get_CATE_bit <- function(data, match_index, index, cur_covs, covs_max_list, column, factor_level, compute_var, num_covs) {
  if (length(index) == 0) {
    if (compute_var) {
      CATE <- setNames(data.frame(matrix(ncol = length(cur_covs)+3, nrow = 0)),
                       c(column[(cur_covs + 1)],"effect","size", "variance"))
    }
    else {
      CATE <- setNames(data.frame(matrix(ncol = length(cur_covs)+2, nrow = 0)),
                       c(column[(cur_covs + 1)],"effect","size"))
    }
  }

  else {
    d = data[match_index,]
    d[,'b_u'] = index
    d[,'b_u'] = unlist(lapply(d[,'b_u'], as.character))
    d[,1:num_covs] <- mapply(function(x,y) factor_level[[x]][d[,y]], 1:num_covs, 1:num_covs)

    summary = data.frame(d %>% group_by(.data$b_u,.data$treated) %>%
                           summarise(size = length(.data$outcome), mean = mean(.data$outcome), variance= var(.data$outcome)))
    summary = data.frame(summary %>% group_by(.data$b_u) %>%
                           summarize(size = sum(.data$size), treated_lst = list(.data$treated), mean_lst = list(.data$mean), var_list = list(.data$variance)))


    pos <- unlist(lapply(summary$b_u, function(x) which(d$b_u %in% x)[1]))
    CATE <- as.data.frame(d[pos, cur_covs + 1])


    CATE$effect = mapply(function(x,y) x[which(y == 1)] - x[which(y == 0)], summary$mean_lst, summary$treated_lst)
    CATE$size = summary$size

    if (compute_var) {
      CATE$variance = mapply(correct_variance, summary$var_list, summary$treated_lst)
      colnames(CATE) = c(column[(cur_covs + 1)],"effect","size", "variance")
    }
    else {
      colnames(CATE) = c(column[(cur_covs + 1)],"effect","size")
    }

    CATE <- CATE[order(CATE$effect),]
    rownames(CATE) = NULL
  }
  return(CATE)
}

correct_variance <- function(x,y) {
  if (is.null(x)) {
    return(0)
  }
  else {
    return((x[which(y == 1)]) + (x[which(y == 0)]))
  }
}

Regression_PE_bit <- function(holdout_trt, holdout_ctl) {

  # MSE for treated
  model_lm <- lm(outcome ~ ., data = holdout_trt) # fit the data to lm model
  MSE_treated <- mean((holdout_trt$outcome - model_lm$fitted.values)^2) # compute mean squared error

  # MSE for control
  model_lm <- lm(outcome ~ ., data = holdout_ctl) # fit the data to lm model
  MSE_control <- mean((holdout_ctl$outcome - model_lm$fitted.values)^2)# compute mean squared error

  return(MSE_treated + MSE_control)
}

GLMNET_PE_bit <- function(holdout_trt, holdout_ctl, lambda, alpha) {

  # MSE for treated
  y <- holdout_trt$outcome
  x <- model.matrix(~ .-1, holdout_trt[,-which(colnames(holdout_trt) == "outcome")])
  fit <- glmnet(x, y, alpha = alpha, lambda = lambda)
  predicted_value <- predict(fit, x, s = lambda)
  MSE_treated <- mean((y - predicted_value)^2) # compute mean squared error

  # MSE for control
  y <- holdout_ctl$outcome
  x <- model.matrix(~ .-1, holdout_ctl[,-which(colnames(holdout_ctl) == "outcome")])
  fit <- glmnet(x, y, alpha = alpha, lambda = lambda)
  predicted_value <- predict(fit, x, s = lambda)
  MSE_control <- mean((y - predicted_value)^2) # compute mean squared error

  return(MSE_treated + MSE_control)
}


#match_quality function takes holdout dataset, number of total covariates,
#list of current covariates, covariate c to temporily remove from, and trafeoff
#parameter as input. The function then computes Balancing Factor and Predictive Error,
#returning Match Quality.

match_quality_bit <- function(c, data, holdout, num_covs, cur_covs, covs_max_list, tradeoff,
                              PE_function, model, ridge_reg, lasso_reg, compute_var) {

  # temporarly remove covariate c
  covs_to_match = cur_covs[cur_covs != c]
  covs_max_to_match = covs_max_list[-which(cur_covs == c)]

  # Calculate number of units unmatched (available)

  num_control = nrow(data[data[,'treated'] == 0,])
  num_treated = nrow(data[data[,'treated'] == 1,])

  # Number of matched units

  match_index = update_matched_bit(data, covs_to_match, covs_max_to_match, compute_var)[[1]]

  num_control_matched = nrow(data[match_index & data[,'treated'] == 0,])
  num_treated_matched = nrow(data[match_index & data[,'treated'] == 1,])

  # Compute Predictive Error

  holdout_trt <- holdout[holdout[,'treated'] == '1',-(c+1)]
  holdout_trt <- holdout_trt[,!(names(holdout_trt) %in% 'treated')]
  holdout_ctl <- holdout[holdout[,'treated'] == '0',-(c+1)]
  holdout_ctl <- holdout_ctl[,!(names(holdout_ctl) %in% 'treated')]

  if (is.null(PE_function)) {

    # default PE - ridge regression with 0.1 regularization parameter
    if (is.null(model)) {
      PE <- GLMNET_PE_bit(holdout_trt, holdout_ctl, lambda = 0.1, alpha = 0)
    }
    else {
      if (model == "Linear") {
        PE <- Regression_PE_bit(holdout_trt, holdout_ctl)
      }

      if (model == "Lasso") {
        if (is.null(lasso_reg)) {
          stop("Please specify lasso_reg regularization parameter.")
        }
        PE <- GLMNET_PE_bit(holdout_trt, holdout_ctl, lambda = lasso_reg, alpha = 1)
      }

      if (model == "Ridge") {
        if (is.null(ridge_reg)) {
          stop("Please specify ridge_reg regularization parameter")
        }
        PE <- GLMNET_PE_bit(holdout_trt, holdout_ctl, lambda = ridge_reg, alpha = 0)
      }
    }
  }

  else {
    # Compute PE based on user defined PE_function
    PE <- PE_function(holdout_trt$outcome, holdout_ctl$outcome, cbind(holdout_trt[,-which(colnames(holdout_trt) == "outcome")]),
                      cbind(holdout_ctl[,-which(colnames(holdout_ctl) == "outcome")]))
  }

  if (num_control == 0 | num_treated == 0) {
    return(-PE)
  } else {
    BF <- num_control_matched/num_control + num_treated_matched/num_treated #Compute Balancing Factor
    return(tradeoff * BF - PE)
  }
}


#' Bit Vectors Implementation
#'
#' \code{FLAME_bit} applies FLAME matching algorithm based on bit vectors.
#' The required arguments include (1) data and (2) holdout. The default model
#' for Match Quality is set to Ridge regression with 0.1 regularization parameter.
#'
#' @param data input data
#' @param holdout holdout training data
#' @param compute_var variance indicator (optional, default = FALSE)
#' @param tradeoff Match Quality tradeoff parameter (optional, default =
#'   0.1)
#' @param PE_function user defined function to compute predictive error
#'   (optional)
#' @param model Linear, Ridge, or Lasso (optional)
#' @param ridge_reg L2 regularization parameter if model = Ridge (optional)
#' @param lasso_reg L1 regularization parameter if model = Lasso (optional)
#' @return (1) list of covariates FLAME performs matching at each iteration, (2)
#' Sizes, conditional average treatment effects (CATEs), and variance (if compute_var = TRUE)
#' of matches at each iteration, (3) match quality at each iteration, and (4) the original
#' data with additional column *matched*, indicating the number of covariates each unit is
#' matched on. If a unit is never matched, then *matched* will be 0.
#' @examples
#' data(toy_data)
#' FLAME_bit(data = toy_data, holdout = toy_data)
#' @import dplyr
#' @import gmp
#' @import glmnet
#' @importFrom rlang .data
#' @importFrom graphics boxplot
#' @importFrom stats rbinom rnorm runif setNames
#' @importFrom stats lm var
#' @export

FLAME_bit <- function(data, holdout, tradeoff = 0.1, compute_var = FALSE, PE_function = NULL,
                      model = NULL, ridge_reg = NULL, lasso_reg = NULL) {

  num_covs = ncol(data) - 2

  # If covariate(s) are not factor(s), then stop
  if (Reduce("|", sapply(1:num_covs, function(x) !is.factor(data[,x] ))) |
      Reduce("|", sapply(1:num_covs, function(x) !is.factor(holdout[,x] )))) {
    stop("Covariates are not factor data type.")
  }

  # If treatment is not factor, then stop
  if (!is.factor(data[,num_covs + 2]) | !is.factor(holdout[,num_covs + 2])) {
    stop("Treatment variable is not factor data type")
  }

  # If outcome variable is not numeric, then stop
  if (!is.numeric(data[,num_covs + 1]) | !is.numeric(holdout[,num_covs + 1])) {
    stop("Outcome variable is not numeric data type")
  }

  factor_level <- lapply(data[,1:num_covs], levels)  # Get levels of each factor
  covs_max_list <- sapply(factor_level, length)   # Get the number of level of each covariate

  # Sort in increasing order
  covs_max_list <- covs_max_list[order(covs_max_list)]
  factor_level <- factor_level[names(covs_max_list)]

  data[,c(1:num_covs)] = data[,names(covs_max_list)]
  colnames(data) <- c(names(covs_max_list), "outcome", "treated")

  holdout[,c(1:num_covs)] = holdout[,names(covs_max_list)]
  colnames(holdout) <- c(names(covs_max_list), "outcome", "treated")

  # add column "matched" to input data
  data$matched <- as.integer(0)
  column <- colnames(data)

  # Convert each covariate and treated into type integer
  data[,c(1:num_covs, num_covs + 2)] <- sapply(data[,c(1:num_covs, num_covs + 2)], function(x) as.integer(x))
  data$treated <- data$treated - 1

  #change input data and holdout training data column name
  colnames(data) <- c(paste("x",seq(0,num_covs-1), sep = ""),"outcome","treated","matched")
  colnames(holdout) <- c(paste("x",seq(0,num_covs-1), sep = ""),"outcome","treated")

  #Set up return objects
  covs_list = list() #list of covariates for matching at each level
  CATE = list() #list of dataframe that calculates conditional average treatment effect at each level
  SCORE = list()

  #Initialize the current covariates to be all covariates and set level to 1
  cur_covs = seq(0,num_covs - 1)
  level = 1

  # Get matched units without dropping anything
  return_match = update_matched_bit(data, cur_covs, covs_max_list, compute_var)
  match_index = return_match[[1]]
  index = return_match[[2]]

  # Set matched = num_covs and get those matched units
  data[match_index,'matched'] = length(cur_covs)
  return_df = data[match_index,]

  covs_list[[level]] <- column[(cur_covs + 1)]
  CATE[[level]] <- get_CATE_bit(data, match_index, index, cur_covs, covs_max_list, column, factor_level, compute_var, num_covs)

  # Remove matched_units
  message(paste("number of matched units =", sum(match_index)))
  data = data[!match_index,]

  #while there are still covariates for matching

  while ((length(cur_covs) > 1) &&
         (sum(data[,'treated'] == 0) > 0) &&
         (sum(data[,'treated'] == 1) > 0)) {

    level = level + 1

    #Temporarily drop one covariate at a time to calculate Match Quality
    #Drop the covariate that returns highest Match Quality Score

    list_score <- unlist(lapply(cur_covs, match_quality_bit, data, holdout, num_covs, cur_covs, covs_max_list,
                                tradeoff, PE_function, model, ridge_reg, lasso_reg, compute_var))
    quality <- max(list_score)

    # randomly sample one covariate to drop
    if (length(quality) > 1) {
      drop <- sample(which(list_score == quality),1)
    }
    else {
      drop <- which(list_score == quality)
    }

    covs_to_drop <- cur_covs[drop]

    cur_covs = cur_covs[! cur_covs %in% covs_to_drop]  #Dropping one covariate

    if (length(cur_covs) == 0) {
      break
    }

    covs_max_list = covs_max_list[-drop]

    SCORE[[level-1]] <- quality
    covs_list[[level]] <- column[(cur_covs + 1)]

    # Update Match
    return_match = update_matched_bit(data, cur_covs, covs_max_list, compute_var)
    match_index = return_match[[1]]
    index = return_match[[2]]

    # Set matched = num_covs and get those matched units
    data[match_index,'matched'] = length(cur_covs)
    return_df = rbind(return_df,data[match_index,])
    CATE[[level]] <- get_CATE_bit(data, match_index, index, cur_covs, covs_max_list, column, factor_level, compute_var, num_covs)

    # Remove matched_units
    data = data[!match_index,]
    message(paste("number of matched units =", sum(match_index)))
  }

  if (nrow(data) != 0) {
    return_df = rbind(return_df,data)
  }
  colnames(return_df) <- column
  rownames(return_df) <- NULL
  return_df[,1:num_covs] <- mapply(function(x,y) factor_level[[x]][return_df[,y]], 1:num_covs, 1:num_covs)
  return_df$index <- 1:nrow(return_df)
  return_list = list(covs_list, CATE, unlist(SCORE), return_df)
  names(return_list) = c("covariate_list", "matched_group", "match_quality", "matched_data")
  return(return_list)
}


#data <- read.csv("/Users/Jerry/Desktop/FLAME Other Document/data_broke_code/this_breaks_FLAME_bit.csv")
#data[,c(1:20,22)] <- lapply(data[,c(1:20,22)], factor)

#holdout <- data
#result_bit <- FLAME::FLAME_bit(data, holdout)
#set.seed(1234)
#data <- FLAME::Data_Generation(ncontrol= 5000, ntreated = 5000, nimportant = 10,
#                               ntrivial= 5, non_linear = 5, U = 5)
#holdout <- data
#result_bit <- FLAME_bit(data, holdout)
#data <- read.csv("/Users/Jerry/Desktop/Natality_db_abnormality.csv")


#tradeoff <- 0.1
#PE_function <- NULL
#model <- NULL
#ridge_reg <- NULL
#lasso_reg <- NULL
#compute_var <- FALSE

