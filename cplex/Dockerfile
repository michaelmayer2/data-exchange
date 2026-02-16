FROM rockylinux:9 

RUN yum install java-25-openjdk-devel -y

COPY pkg/cos_installer_preview-22.1.2.R4-M0N96ML-linux-x86-64.bin /

COPY install.response / 
RUN bash /cos_installer_preview-22.1.2.R4-M0N96ML-linux-x86-64.bin -i silent -f install.response

ENV R_VERSION=4.5.2
RUN yum install epel-release -y && crb enable

RUN yum install -y https://cdn.posit.co/r/rhel-9/pkgs/R-${R_VERSION}-1-1.$(arch).rpm

RUN /opt/R/${R_VERSION}/bin/R -q -e 'options(repos="https://p3m.dev/cran/__linux__/rhel9/latest"); install.packages("pak")' 

RUN CPLEX_BIN="/usr/local/cplex/22.1.2/cplex/bin/x86-64_linux/cplex"  /opt/R/${R_VERSION}/bin/R -q -e 'options(repos="https://p3m.dev/cran/__linux__/rhel9/latest"); pak::pak("Rcplex")'  
