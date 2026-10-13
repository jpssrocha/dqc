"""Stage One processing module for the linear-fit scenario (``sec:testing``).

The user-submitted container payload that "Job Execution"/``ApptainerExecutor``
runs inside the sandbox: it reads the apparatus CSV (``x``, ``y``), fits a
linear model by gradient descent, and writes the result next to the input. Per
the plan's Stage One this recovers the angular and linear coefficients; the
prototype problem (``ficticious_problem.md``) notes the coefficients should be
emitted as JSON so Stage Two can consume them. This spike instead writes the
residuals back out as CSV. Under the one-to-one file-to-job mapping of
``sec:detailed-spec`` this module corresponds to exactly one ``JobManifest``.
"""

import jax
import jax.random as jr
import jax.numpy as jnp
import numpy as np
import pandas
 
import csv

def cost(x, y):
    """Return the mean-squared-error loss for the line ``a*x + b``."""

    def loss(a, b):
        y_pred = a*x + b
        return  jnp.mean(jnp.square(y - y_pred))

    return loss


def fit(x, y, a0 = 1., b0 = 0., N  = 100, lr=0.1):
    """Gradient-descent fit of ``a`` (angular) and ``b`` (linear) coefficients."""

    a = a0
    b = b0

    dL = jax.grad(cost(x, y))
    
    for _ in range(N):

        da, db = dL(a, b)

        a -= lr*da
        b -= lr*db

    return (a, b)
    
 

def main(input):
    """Stage One entry point invoked by the worker for one apparatus CSV."""
    # load data from csv
    x,y = np.genfromtxt(input, skip_header=1).T

    # fit line
    a, b = fit(x, y)
    print(a, b)

    # save results as csv again
    y_rotated = y - (a*y + b)

    data = np.vstack([x, y_rotated])

    print(data.shape)

    np.savetxt("output.csv", data,comments="", header="x,y")

if __name__ == "__main__":
    # main("../dqc_test/test_data/linear_2026-09-25_14:36:30.270593.csv")

    input = "../dqc_test/test_data/linear_2026-09-25_14:36:30.270593.csv"

    # load data from csv
    x,y = np.genfromtxt(input, skip_header=1).T

    # fit line
    a, b = fit(x, y)
    print(a, b)

    # save results as csv again
    y_rotated = y - (a*y + b)

    data = np.vstack([x, y_rotated])

    print(data.shape)

    np.savetxt("output.csv", data,comments="", header="x,y")
