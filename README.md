# Red Hat OpenShift AI (RHOAI) Installer

This repository provides a **GitOps-ready** installer for a reliable deployment of Red Hat OpenShift AI. The process packages all logic into a Kubernetes `Job` that runs directly inside the cluster, ensuring a repeatable and declarative setup.

This script installs the following components in the correct order:

* Node Feature Discovery (NFD) Operator
* OpenShift Service Mesh Operator
* OpenShift Serverless Operator
* Authorino Operator
* Red Hat OpenShift AI Operator and a default `DataScienceCluster` instance.

***

## Prerequisites

* `oc` and `kustomize` CLIs installed locally.
* `cluster-admin` access to an OpenShift cluster.

***

## Installation

1.  **Create the installer's namespace:**
    ```bash
    oc apply -f 00-installer-namespace.yaml
    ```

2.  **Run the installer job:**
    ```bash
    kustomize build . | oc apply -f -
    ```

3.  **Monitor the installation progress:**
    ```bash
    oc logs -f -n redhat-ods-operator $(oc get pods -n redhat-ods-operator -l job-name=rhoai-installer-job -o name)
    ```

The installation is complete when the logs show `🚀🚀🚀 DEPLOYMENT COMPLETE 🚀🚀🚀`.
