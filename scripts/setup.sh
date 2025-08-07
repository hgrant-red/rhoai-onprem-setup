#!/bin/bash
# This script automates the installation of OpenShift AI and its dependencies.
# It is designed to be run as an in-cluster Job.

set -eo pipefail

# ===================================================================================
# --- HELPER FUNCTION ---
# ===================================================================================

# A robust, data-driven function to wait for an operator to install and become ready.
# It discovers the deployment names directly from the operator's ClusterServiceVersion (CSV).
# Usage: wait_for_operator <namespace> <subscription_name>
wait_for_operator() {
  local namespace=$1
  local subscription_name=$2
  local timeout=900 # 15-minute timeout for resilience on slow clusters

  echo "--> Waiting for Subscription '$subscription_name' in namespace '$namespace' to be processed by OLM..."
  
  # 1. Wait for the Subscription to report the name of the CSV it is installing
  local start_time=$(date +%s)
  local csv_name=""
  until [[ -n "$csv_name" ]]; do
    csv_name=$(oc get subscription "$subscription_name" -n "$namespace" -o jsonpath='{.status.installedCSV}' 2>/dev/null || echo "")
    if [[ -n "$csv_name" ]]; then
      if ! oc get csv "$csv_name" -n "$namespace" &> /dev/null; then
        csv_name="" # CSV is not created yet, keep waiting
      fi
    fi
    local current_time=$(date +%s)
    if (( current_time - start_time > timeout )); then
      echo "ERROR: Timed out waiting for Subscription '$subscription_name' to create a CSV."
      oc get subscription "$subscription_name" -n "$namespace" -o yaml
      exit 1
    fi
    sleep 5
  done

  echo "--> Found CSV: '$csv_name'. Waiting for it to succeed..."

  # 2. Use a robust 'until' loop to poll for the 'Succeeded' phase. This avoids the 'oc wait' bug.
  start_time=$(date +%s)
  local current_phase=""
  until [[ "$current_phase" == "Succeeded" ]]; do
    current_phase=$(oc get csv "$csv_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Installing")
    echo "--> Current phase for '$csv_name' is '$current_phase'..."
    local current_time=$(date +%s)
    if (( current_time - start_time > timeout )); then
      echo "ERROR: Timed out waiting for CSV '$csv_name' to reach 'Succeeded' phase."
      oc get csv "$csv_name" -n "$namespace" -o yaml
      exit 1
    fi
    sleep 10
  done
  
  echo "--> CSV '$csv_name' is ready. Discovering its deployments..."

  # 3. Inspect the CSV to get the names of the deployments it creates
  local deployment_names
  deployment_names=$(oc get csv "$csv_name" -n "$namespace" -o jsonpath='{.spec.install.spec.deployments[*].name}')
  
  if [ -z "$deployment_names" ]; then
    echo "--- ✅ Operator '$subscription_name' has no deployments to wait for. Continuing. ---"
    return
  fi
  
  echo "--> Found deployments to wait for: $deployment_names"

  # 4. Loop through the discovered deployment names and wait for each one
  for deployment_name in $deployment_names; do
    echo "--> Waiting for deployment '$deployment_name' to become available..."
    oc wait deployment -n "$namespace" "$deployment_name" --for condition=Available=True --timeout="${timeout}s"
  done
  
  echo "--- ✅ Operator '$subscription_name' and all its deployments are ready."
}


# ===================================================================================
# --- MAIN EXECUTION ---
# ===================================================================================

echo "--- STEP 1: Applying NFD Operator..."
oc apply -f /manifests/operators/10-nfd-operator.yaml
wait_for_operator openshift-nfd nfd
oc apply -f /manifests/configs/10-nfd-instance.yaml
echo "--- ✅ NFD Operator setup is complete."


echo "--- STEP 2: Applying Service Mesh Operator..."
oc apply -f /manifests/operators/05-service-mesh-operator.yaml
wait_for_operator openshift-operators servicemeshoperator


echo "--- STEP 3: Applying Serverless Operator..."
oc apply -f /manifests/operators/06-serverless-operator.yaml
wait_for_operator openshift-serverless serverless-operator


echo "--- STEP 4: Applying Authorino Operator..."
oc apply -f /manifests/operators/30-authorino-operator.yaml
wait_for_operator authorino-operator authorino-operator


# ===================================================================================
# --- STEP 5: Applying NVIDIA GPU Operator (COMMENTED OUT) ---
# This block is ready for the on-premises environment with GPUs.
# ===================================================================================
echo "--- STEP 5: Applying NVIDIA GPU Operator..."
oc apply -f /manifests/operators/20-gpu-operator.yaml
wait_for_operator nvidia-gpu-operator gpu-operator-certified

echo "--- Applying GPU ClusterPolicy to begin driver installation..."
oc apply -f /manifests/configs/20-gpu-clusterpolicy.yaml
echo "--- ✅ NVIDIA GPU Operator setup is initiated. NOTE: Driver installation will be pending until GPUs are present."
# ===================================================================================


echo "--- STEP 6: Applying Red Hat OpenShift AI Operator..."
oc apply -f /manifests/operators/40-rhoai-operator.yaml
wait_for_operator redhat-ods-operator rhods-operator


echo "--- STEP 7: Applying DataScienceCluster Resource..."
echo "--> Waiting for the 'redhat-ods-applications' namespace to be created by the operator..."
until oc get ns redhat-ods-applications &> /dev/null; do
  echo "Still waiting for 'redhat-ods-applications' namespace..."
  sleep 10
done
oc apply -f /manifests/configs/30-datasciencecluster.yaml

echo "--> Waiting for the DataScienceCluster 'default-dsc' to become ready (This may take up to 15 minutes)..."
oc wait datasciencecluster default-dsc -n redhat-ods-applications --for condition=Ready --timeout=900s
echo "--- ✅ DataScienceCluster is ready."


echo "--- STEP 8: Applying Dashboard Customizations..."
oc patch -n redhat-ods-applications OdhDashboardConfig odh-dashboard-config --type=merge -p '{"spec":{"dashboardConfig":{"disableModelCatalog":false,"disableHardwareProfiles":false}}}'
echo "--- ✅ Dashboard customizations applied."


echo ""
echo "🚀🚀🚀 DEPLOYMENT COMPLETE 🚀🚀🚀"
echo "Red Hat OpenShift AI has been successfully installed."
