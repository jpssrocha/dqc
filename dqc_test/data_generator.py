"""Data generator for the linear-fit test scenario (``sec:testing``).

Produces the synthetic apparatus output used throughout the "Testing plan" and
the prototype problem (see ``ficticious_problem.md``): an apparatus sweeps a
controlled variable across N positions and measures a dependent variable,
writing a CSV with columns ``x`` and ``y`` (Stage One / Stage Two pipeline
input). The Streamlit UI below is the interactive fixture used to drop these
CSVs into ``test_data`` so the runtime and job-execution spikes have something
to consume; the integration tests in ``sec:integration-tests`` call the
underlying generator directly.
"""

import random
from datetime import datetime
from pathlib import Path

import streamlit as st
from jax import jit
import jax.random as jr
import jax.numpy as jnp
import numpy as np
import matplotlib.pyplot as plt
import polars as pl
import pandas as pd


def generate_random_linear_dataset(
    seed: int, N: int,
    *,
    alpha: float = 1.0,
    beta: float = 0.0,
    sigma: float = 1.0,
    xlim: tuple[int, int] = (-1, 1)
  ) -> dict:
    """
    Given a random seed `seed`, a number of points `N`, an angular coefficient
    `alpha`, a linear coefficient `beta` and a standard deviation `sigma`.
    Generates  a cloud of points (x, y) from that line.

    Drives the linear-fit scenario of ``sec:testing``: ``alpha`` is the Stage
    One angular coefficient and ``beta`` the linear coefficient that the
    pipeline is expected to recover.
    """

    key = jr.key(seed)

    xkey, ykey = jr.split(key)

    xs = jr.uniform(xkey, shape=(N,), minval=xlim[0], maxval=xlim[1])
    ys = alpha*xs + beta + sigma*jr.normal(ykey, shape=(N,))

    
    return  { "x": xs, "y": ys }


def main():
    """Launch the interactive fixture that writes apparatus CSVs to ``test_data``.

    Each saved file represents one apparatus run and, per the one-to-one
    file-to-job simplification in ``sec:detailed-spec``, exactly one DQC job.
    """

    st.set_page_config(page_title="Simple Data Generator", layout="wide")
    
    STEM = "linear"
    DATA_FOLDER = Path("test_data")

    DATA_FOLDER.mkdir(exist_ok=True)
    SEED = random.randint(0, int(1e9))

    st.title("Generate Random Linear Dataset")
    

    alpha = st.slider(r"$\alpha$", min_value=-5.0, max_value=5.0, step=0.5, value=0.0)
    beta = st.slider(r"$\beta$", min_value=-5.0, max_value=5.0, step=0.5, value=0.0)
    sigma = st.slider(r"$\sigma$", min_value=0.0, max_value=5.0, step=0.2, value=1.0)


    data = generate_random_linear_dataset(SEED, 50, alpha=alpha, beta=beta, sigma=sigma, xlim=(-5, 5))

    fig, ax = plt.subplots(figsize=(6, 3))
    ax.scatter(**data)
    ax.set(ylim=(-5, 5))
    fig.tight_layout()

    with st.container(horizontal_alignment="center"):
        st.pyplot(plt, width="content")

        if st.button("Save"):
            stamp = f"{STEM}_{str(datetime.now()).replace(" ", "_")}.csv"
            pd.DataFrame(data).to_csv(DATA_FOLDER / stamp, index=False)
            st.markdown(f"Saved: {stamp}")

    

    return None

if __name__ == "__main__":
    main()
