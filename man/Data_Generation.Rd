% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/Data_Generation.R
\name{Data_Generation}
\alias{Data_Generation}
\title{Generate Synthetic Data}
\usage{
Data_Generation(ncontrol, ntreated, nimportant, ntrivial, non_linear, U)
}
\arguments{
\item{ncontrol}{number of samples in the control group}

\item{ntreated}{number of samples in the treated group}

\item{nimportant}{number of important covariates}

\item{ntrivial}{number of unimportant covariates}

\item{non_linear}{number of covariates with non-linear relationship}

\item{U}{coefficient of non-linear term}
}
\value{
synthetic data
}
\description{
\code{Data_Generation} generates synthetic data, where each covariate is a
binary variable.
}
\examples{
Data_Generation(10, 10, 10, 5, 5, 5)

}
