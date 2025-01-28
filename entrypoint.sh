#!/bin/bash
# Create symbolic links dynamically
mkdir -p /data/BUSCO_libs && ln -sf /data/BUSCO_libs /opt/TEammo/BUSCO_libs
# mkdir -p /data/0_raw && ln -sf /data/0_raw /opt/TEammo/0_raw
ln -sf /data/0_raw /opt/TEammo/0_raw
mkdir -p /data/MCH_output && ln -sf /data/MCH_output /opt/TEammo/MCH_output
mkdir -p /data/RM2_output && ln -sf /data/RM2_output /opt/TEammo/RM2_output

