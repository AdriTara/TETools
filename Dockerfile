# Dfam TE Tools container including RepeatMasker, RepeatModeler, coseg

FROM debian:12 AS builder

ARG TARGETARCH

RUN apt-get -y update && apt-get -y install \
    gcc \
    g++ \
    make \
    zlib1g-dev \
    libgomp1 \
    perl \
    python3-h5py \
    libfile-which-perl \
    libtext-soundex-perl \
    libjson-perl liburi-perl libwww-perl \
    libdevel-size-perl \
    aptitude && aptitude install -y ~pstandard ~prequired \
    curl wget \
    vim nano \
    procps strace \
    libpam-systemd- \
    python3-setuptools \
    locales
  
COPY src/* /opt/src/
COPY sha256sums.txt /opt/src/
WORKDIR /opt/src

RUN if [ "$TARGETARCH" = "amd64" ]; then \
        sha256sum -c sha256sums.txt; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
        mv sha256sums.txt /opt; \
        cat /opt/sha256sums.txt | shasum -a 256 -c; \ 
        rm /opt/sha256sums.txt; \
    fi

# Extract RMBlast
RUN mkdir /opt/rmblast && \
    if [ "$TARGETARCH" = "amd64" ]; then \
        tar --strip-components=1 -x -f /opt/src/rmblast-2.14.1+-x64-linux.tar.gz -C /opt/rmblast; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
        tar --strip-components=1 -x -f /opt/src/rmblast-2.14.1+-arm64-macosx.tar.gz -C /opt/rmblast; \ 
    fi

# Compile HMMER
RUN tar -x -f hmmer-3.4.tar.gz \
    && cd hmmer-3.4 \
    && ./configure --prefix=/opt/hmmer && make && make install \
    && make clean

# Compile TRF
RUN tar -x -f trf-4.09.1.tar.gz \
    && cd TRF-4.09.1 \
    && mkdir build && cd build \
    && ../configure && make && cp ./src/trf /opt/trf \
    && cd .. && rm -r build

# Compile RepeatScout
RUN tar -x -f RepeatScout-1.0.7.tar.gz \
    && cd RepeatScout-1.0.7 \
    && mv README.md README \
    && sed -i 's#^INSTDIR =.*#INSTDIR = /opt/RepeatScout#' Makefile \
    && make install

# Compile and configure RECON
RUN tar -x -f RECON-1.08.tar.gz \
    && mv RECON-1.08 ../RECON \
    && cd ../RECON \
    && make -C src && make -C src install \
    && cp 00README bin/ \
    && sed -i 's#^\$path =.*#$path = "/opt/RECON/bin";#' scripts/recon.pl

# Compile cd-hit
RUN tar -x -f cd-hit-v4.8.1-2019-0228.tar.gz \
    && cd cd-hit-v4.8.1-2019-0228 \
    && make && mkdir /opt/cd-hit && PREFIX=/opt/cd-hit make install

# Compile genometools (for ltrharvest)
RUN tar -x -f gt-1.6.4.tar.gz \
    && cd genometools-1.6.4 \
    && make -j4 cairo=no && make cairo=no prefix=/opt/genometools install \
    && make cleanup

# Configure LTR_retriever
RUN cd /opt \
    && tar -x -f src/LTR_retriever-2.9.0.tar.gz \
    && mv LTR_retriever-2.9.0 LTR_retriever \
    && cd LTR_retriever \
    && sed -i \
        -e 's#BLAST+=#BLAST+=/opt/rmblast/bin#' \
        -e 's#RepeatMasker=#RepeatMasker=/opt/RepeatMasker#' \
        -e 's#HMMER=#HMMER=/opt/hmmer/bin#' \
        -e 's#CDHIT=#CDHIT=/opt/cd-hit#' \
        -e 's#TEsorter=#TEsorter=/opt/TEsorter/dist#' \
        paths

# Compile MAFFT
RUN tar -x -f mafft-7.471-without-extensions-src.tgz \
    && cd mafft-7.471-without-extensions/core \
    && sed -i 's#^PREFIX =.*#PREFIX = /opt/mafft#' Makefile \
    && make clean && make && make install \
    && make clean

# Compile NINJA
RUN cd /opt \
    && tar --strip-components=1 -x -f src/NINJA-cluster.tar.gz \
    && cd NINJA \
    && make clean && make all \
    && cd .. \
    && mv LICENSE ./NINJA \
    && mv README.md ./NINJA 
    
# Move UCSC tools
RUN mkdir /opt/ucsc_tools && \
    if [ "$TARGETARCH" = "amd64" ]; then \
        mv /opt/src/faToTwoBit_x86 /opt/ucsc_tools/faToTwoBit; \
        mv /opt/src/twoBitInfo_x86 /opt/ucsc_tools/twoBitInfo; \
        mv /opt/src/twoBitToFa_x86 /opt/ucsc_tools/twoBitToFa; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
        mv /opt/src/faToTwoBit_arm64 /opt/ucsc_tools/faToTwoBit;  \
        mv /opt/src/twoBitInfo_arm64 /opt/ucsc_tools/twoBitInfo; \
        mv /opt/src/twoBitToFa_arm64 /opt/ucsc_tools/twoBitToFa; \
    fi 
COPY LICENSE.ucsc /opt/ucsc_tools/LICENSE

# Compile and configure coseg
RUN cd /opt \
    && mkdir coseg \
    && tar -x -f src/coseg-0.2.3.tar.gz -C ./coseg \
    && cd coseg/coseg-coseg-0.2.3 \
    && mv * ../ \
    && cd ../ \
    && sed -i 's@#!.*perl@#!/usr/bin/perl@' preprocessAlignments.pl runcoseg.pl refineConsSeqs.pl \
    && sed -i 's#use lib "/usr/local/RepeatMasker";#use lib "/opt/RepeatMasker";#' preprocessAlignments.pl \
    && make

# Configure RepeatMasker
# With Minimal TE Library
#   - Also with full Dfam curated RepeatMasker.lib for RepeatClassifier
RUN cd /opt \
    && tar -x -f src/RepeatMasker-4.1.7-p1.tar.gz \
    && chmod a+w RepeatMasker/Libraries \
    && chmod a+w RepeatMasker/Libraries/famdb \
    && cd RepeatMasker \
    && perl configure \
        -hmmer_dir=/opt/hmmer/bin \
        -rmblast_dir=/opt/rmblast/bin \
        -libdir=/opt/RepeatMasker/Libraries \
        -trf_prgm=/opt/trf \
        -default_search_engine=rmblast \
    && gunzip -c /opt/src/Dfam-RepeatMasker.lib.gz > Libraries/RepeatMasker.lib \
    && /opt/rmblast/bin/makeblastdb -dbtype nucl -in Libraries/RepeatMasker.lib \
    && cd ..

# With Dfam root partition
#RUN cd /opt \
#    && tar -x -f src/RepeatMasker-4.1.6.tar.gz \
#    && chmod a+w RepeatMasker/Libraries \
#    && chmod a+w RepeatMasker/Libraries/famdb \
#    && gunzip src/dfam38_full.0.h5.gz \
#    && mv src/dfam38_full.0.h5 /opt/RepeatMasker/Libraries/famdb/dfam38_full.0.h5 \
#    && cd RepeatMasker \
#    && perl configure \
#        -hmmer_dir=/opt/hmmer/bin \
#        -rmblast_dir=/opt/rmblast/bin \
#        -libdir=/opt/RepeatMasker/Libraries \
#        -trf_prgm=/opt/trf \
#        -default_search_engine=rmblast \
#    && gunzip -c src/Dfam-RepeatMasker.lib.gz > RepeatMasker/Libraries/RepeatMasker.lib \
#    && /opt/rmblast/bin/makeblastdb -dbtype nucl -in RepeatMasker/Libraries/RepeatMasker.lib \
#    && cd ..

# Include config update
COPY tetoolsDfamUpdate.pl /opt/RepeatMasker/tetoolsDfamUpdate.pl

# Configure RepeatModeler
RUN cd /opt \
    && tar -x -f src/RepeatModeler-2.0.6.tar.gz \
    && mv RepeatModeler-2.0.6 RepeatModeler \
    && cd RepeatModeler \
    && perl configure \
         -cdhit_dir=/opt/cd-hit -genometools_dir=/opt/genometools/bin \
         -ltr_retriever_dir=/opt/LTR_retriever -mafft_dir=/opt/mafft/bin \
         -ninja_dir=/opt/NINJA -recon_dir=/opt/RECON/bin \
         -repeatmasker_dir=/opt/RepeatMasker \
         -rmblast_dir=/opt/rmblast/bin -rscout_dir=/opt/RepeatScout \
         -trf_dir=/opt \
         -ucsctools_dir=/opt/ucsc_tools

RUN echo "PS1='(dfam-tetools \$(pwd))\\\$ '" >> /etc/bash.bashrc

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen
ENV LANG en_US.UTF-8  
ENV LANGUAGE en_US:en  
ENV LC_ALL en_US.UTF-8     

ENV PYTHONIOENCODING=utf8
ENV PATH=/opt/RepeatMasker:/opt/RepeatMasker/util:/opt/RepeatModeler:/opt/RepeatModeler/util:/opt/coseg:/opt/ucsc_tools:/opt:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/opt/rmblast/bin:/bin:/opt/cd-hit:/opt/mafft/bin

RUN chmod +x /opt/ucsc_tools/* \
    && rm -r /opt/src
    
    
# MCHelper installation
RUN apt install -y git unzip python3-pandas python3-opencv python3-psutil python3-sklearn r-base python3-opencv && \
    pip install --break-system-packages pdf2image Bio

# TEammo
## Uncomment when TEammo repository is public, while use the src option
# RUN git clone --recurse-submodules git@github.com:/AdriTara/TEammo.git /opt/TEammo
RUN apt install -y libssl-dev libcurl4-openssl-dev
COPY TEammo/TEammo_install.R /TEammo_install.R
RUN Rscript /TEammo_install.R
COPY TEammo /opt/TEammo
WORKDIR /opt/TEammo


COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

CMD ["bash"]

#CMD ["Rscript", "TEammo_app.R"]

#RUN git clone https://github.com/AdriTara/MCHelper /opt/MCHelper && \
#    cd /opt/MCHelper/db && unzip "*.zip" && makeblastdb -in allDatabases.clustered_rename.fa -dbtype nucl
#if want to run the test
# python3 MCHelper.py -r A -t 20 -i Test_dir/repet_input/ -o Test_dir/repet_output_own/ -g Test_dir/repet_input/Dmel_genome.fasta --input_type repet -b Test_dir/repet_input/diptera_odb10.hmm -a F -n Dmel

# HELIANO

#RUN git clone 



