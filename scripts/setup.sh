#!/bin/bash
set -eo pipefail

echo "--- STEP 1: Applying NFD Operator..."

echo "STEP 1: Installing NFD Operator..."
oc apply -f operators/10-nfd-operator.yaml
echo "INFO: Pausing for 60 seconds to allow OLM to process the request..."
sleep 60

oc apply -f /operators/10-nfd-operator.yaml
oc wait deployment -n openshift-nfd nfd-controller-manager --for condition=Available=True --timeout=300s
oc apply -f /configs/10-nfd-instance.yaml
echo "--- ✅ NFD Operator is ready."

echo "--- STEP 2: Applying Service Mesh & Serverless..."
oc apply -f /operators/05-service-mesh-operator.yaml
oc apply -f /operators/06-serverless-operator.yaml
echo "--- Waiting for dependencies to be ready..."
oc wait --for=condition=established crd/servicemeshcontrolplanes.maistra.io --timeout=300s
oc wait --for=condition=established crd/knativeservings.operator.knative.dev --timeout=300s
echo "--- ✅ Dependencies are ready."

# ===================================================================================
# --- STEP 3: Applying NVIDIA GPU Operator (COMMENTED OUT FOR AWS TEST) ---
# ===================================================================================
# echo "--- STEP 3: Applying NVIDIA GPU Operator..."
# oc apply -f /operators/20-gpu-operator.yaml
#
# echo "--- Waiting for NVIDIA GPU Operator to install..."
# CSV_NAME_GPU=""
# until [ ! -z "$CSV_NAME_GPU" ]; do
#   CSV_NAME_GPU=$(oc get sub gpu-operator-certified -n nvidia-gpu-operator -o jsonpath='{.status.installedCSV}' 2>/dev/null || echo "")
#   echo "Waiting for NVIDIA GPU Operator installation plan..."
#   sleep 10
# done
# oc wait csv $CSV_NAME_GPU -n nvidia-gpu-operator --for condition=Succeeded --timeout=300s
# echo "--- ✅ NVIDIA GPU Operator is running."
#
# echo "--- Applying GPU ClusterPolicy to begin driver installation..."
# oc get csv -n nvidia-gpu-operator $CSV_NAME_GPU -ojsonpath='{.metadata.annotations.alm-examples}' | jq '.[0]' > /tmp/20-gpu-clusterpolicy.yaml
# oc apply -f /tmp/20-gpu-clusterpolicy.yaml
#
# echo "--- WAITING FOR NVIDIA DRIVERS TO DEPLOY (This can take 10-20 minutes)..."
# until oc wait pod -n nvidia-gpu-operator -l openshift.driver-toolkit --for condition=Ready=True --timeout=600s 2>/dev/null; do
#   echo "Driver pods not ready yet. Retrying in 30 seconds..."
#   sleep 30
# done
# echo "--- ✅ NVIDIA GPU drivers are fully deployed and ready."
# ===================================================================================

echo "--- STEP 4: Applying Authorino & RHOAI Operators..."
oc apply -f /operators/30-authorino-operator.yaml
oc apply -f /operators/40-rhoai-operator.yaml

echo "--- Waiting for RHOAI Operator to be ready..."
oc wait --for=condition=established crd/datascienceclusters.datasciencecluster.opendatahub.io --timeout=300s
echo "--- ✅ RHOAI Operator is ready."

echo "--- STEP 5: Applying DataScienceCluster resource..."
until oc get ns redhat-ods-applications 2>/dev/null; do
  echo "Waiting for 'redhat-ods-applications' namespace to be created..."
  sleep 10
done
oc apply -f /configs/30-datasciencecluster.yaml

echo "--- Waiting for DataScienceCluster to be ready..."
oc wait datasciencecluster default-dsc -n redhat-ods-applications --for condition=Ready --timeout=900s

echo "--- STEP 6: Applying Dashboard Customizations..."
oc patch -n redhat-ods-applications OdhDashboardConfig odh-dashboard-config --type=merge -p '{"spec":{"dashboardConfig":{"disableModelCatalog":false,"disableHardwareProfiles":false}}}'

echo "--- ✅ DEPLOYMENT COMPLETE ---"
