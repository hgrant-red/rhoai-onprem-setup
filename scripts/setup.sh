#!/bin/bash
# This script automates the installation of OpenShift AI and its dependencies.
# It is designed to be run as an in-cluster Job.

set -eo pipefail

# ===================================================================================
# --- HELPER FUNCTIONS ---
# ===================================================================================

# A robust function to wait for a CRD to exist and then become established.
# Usage: wait_for_crd <crd_name>
# Example: wait_for_crd servicemeshcontrolplanes.maistra.io
wait_for_crd() {
  local crd_name=$1
  local timeout=300 # 5-minute timeout

  echo "--> Waiting for CRD '$crd_name' to be created..."
  local start_time=$(date +%s)
  until oc get crd "$crd_name" &> /dev/null; do
    local current_time=$(date +%s)
    if (( current_time - start_time > timeout )); then
      echo "ERROR: Timed out waiting for CRD '$crd_name' to be created."
      exit 1
    fi
    sleep 5
  done

  echo "--> CRD '$crd_name' found. Waiting for it to become established..."
  oc wait --for=condition=Established "crd/$crd_name" --timeout="${timeout}s"
  echo "--- ✅ CRD '$crd_name' is ready."
}

# Waits for a specific deployment to become available in a namespace.
# Usage: wait_for_deployment <namespace> <deployment_name>
wait_for_deployment() {
    local namespace=$1
    local deployment_name=$2
    local timeout=300 # 5-minute timeout

    echo "--> Waiting for deployment '$deployment_name' in namespace '$namespace' to be created..."
    local start_time=$(date +%s)
    until oc get deployment "$deployment_name" -n "$namespace" &> /dev/null; do
      local current_time=$(date +%s)
      if (( current_time - start_time > timeout )); then
        echo "ERROR: Timed out waiting for deployment '$deployment_name' to be created."
        exit 1
      fi
      sleep 5
    done

    echo "--> Deployment '$deployment_name' found. Waiting for it to become available..."
    oc wait deployment -n "$namespace" "$deployment_name" --for condition=Available=True --timeout="${timeout}s"
    echo "--- ✅ Deployment '$deployment_name' is ready."
}


# ===================================================================================
# --- MAIN EXECUTION ---
# ===================================================================================

echo "--- STEP 1: Applying NFD Operator..."
oc apply -f /manifests/operators/10-nfd-operator.yaml
wait_for_crd nodefeaturediscoveries.nfd.openshift.io
wait_for_deployment openshift-nfd nfd-controller-manager
oc apply -f /manifests/configs/10-nfd-instance.yaml
echo "--- ✅ NFD Operator setup is complete."


echo "--- STEP 2: Applying Service Mesh, Serverless, and Authorino Operators..."
oc apply -f /manifests/operators/05-service-mesh-operator.yaml
oc apply -f /manifests/operators/06-serverless-operator.yaml
oc apply -f /manifests/operators/30-authorino-operator.yaml

echo "--- Waiting for core dependency operators to be ready..."
wait_for_crd servicemeshcontrolplanes.maistra.io
wait_for_crd knativeservings.operator.knative.dev
wait_for_crd authorinos.authorino.kuadrant.io
echo "--- ✅ Core dependency operators are ready."


# ===================================================================================
# --- STEP 3: Applying NVIDIA GPU Operator (COMMENTED OUT) ---
# This block is ready for the on-premises environment.
# ===================================================================================
# echo "--- STEP 3: Applying NVIDIA GPU Operator..."
# oc apply -f /manifests/operators/20-gpu-operator.yaml
# wait_for_crd clusterpolicies.nvidia.com
# wait_for_deployment nvidia-gpu-operator gpu-operator
#
# echo "--- Applying GPU ClusterPolicy to begin driver installation..."
# oc apply -f /manifests/configs/20-gpu-clusterpolicy.yaml
#
# echo "--- WAITING FOR NVIDIA DRIVERS TO DEPLOY (This can take over 15 minutes)..."
# until oc get clusterpolicy/gpu-cluster-policy -o jsonpath='{.status.state}' | grep -q "ready"; do
#   echo "Driver state is not 'ready' yet. Checking again in 30 seconds..."
#   sleep 30
# done
# echo "--- ✅ NVIDIA GPU drivers are fully deployed and ready."
# ===================================================================================


echo "--- STEP 4: Applying Red Hat OpenShift AI Operator..."
oc apply -f /manifests/operators/40-rhoai-operator.yaml
wait_for_crd datascienceclusters.datasciencecluster.opendatahub.io
echo "--- ✅ RHOAI Operator is ready."


echo "--- STEP 5: Applying DataScienceCluster Resource..."
echo "--> Waiting for the 'redhat-ods-applications' namespace to be created by the operator..."
until oc get ns redhat-ods-applications &> /dev/null; do
  echo "Still waiting for 'redhat-ods-applications' namespace..."
  sleep 10
done
oc apply -f /manifests/configs/30-datasciencecluster.yaml

echo "--> Waiting for the DataScienceCluster 'default-dsc' to become ready (This may take several minutes)..."
oc wait datasciencecluster default-dsc -n redhat-ods-applications --for condition=Ready --timeout=900s
echo "--- ✅ DataScienceCluster is ready."


echo "--- STEP 6: Applying Dashboard Customizations..."
oc patch -n redhat-ods-applications OdhDashboardConfig odh-dashboard-config --type=merge -p '{"spec":{"dashboardConfig":{"disableModelCatalog":false,"disableHardwareProfiles":false}}}'
echo "--- ✅ Dashboard customizations applied."


echo ""
echo "🚀🚀🚀 DEPLOYMENT COMPLETE 🚀🚀🚀"
echo "Red Hat OpenShift AI has been successfully installed."
