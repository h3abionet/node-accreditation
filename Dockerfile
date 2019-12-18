FROM nfcore/base
LABEL authors="Chris Fields" \
      description="Docker image containing all requirements for nf-core/subdata pipeline"

COPY environment.yml /
RUN conda env create -f /environment.yml && conda clean -a
ENV PATH /opt/conda/envs/nf-core-subdata-1.0dev/bin:$PATH
