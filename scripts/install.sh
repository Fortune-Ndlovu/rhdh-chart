#!/bin/bash

#  Copyright (c) 2024 Red Hat, Inc.
#  Licensed under the Apache License, Version 2.0 (the "License");
#  You may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
# Script to handle CLI Helm installation and management of OCP resources
#
# Requires: oc, helm, and an active login session to a cluster.

set -e

# Static Variables
export NAME_SPACE=rhdh
export CLUSTER_USERNAME=kubeadmin
export RELEASE_NAME=backstage
export HELM_CHART_VALUE_FILE_NAME='./testing-audit-log-and-rbac.yaml'
export HELM_REPO_NAME=openshift-helm-charts
export HELM_REPO_URL=https://charts.openshift.io/

# Dynamic Variables
export CLUSTER_PASSWORD=IJryK-x5A3H-mZPzR-KrbAz
export CLUSTER_API=https://api.crc.testing:6443
export CLUSTER_ROUTER_BASE=apps-crc.testing

usage() {
    echo "
This script simplifies and automates the installation and management of Helm charts on the OpenShift Container Platform (OCP) clusters.
It includes installation of required tools, Helm chart installation, and OpenShift resource management.

Usage:
  $0 [OPTIONS]

Options:
  --router-base <router-base> : Manually provide the cluster router base if auto-detection fails.
  --release-name <name>       : Specify a custom release name for the Helm chart.
  --generate-name             : Generate a name for the Helm release (overrides --release-name).
  --namespace <namespace>     : Specify the namespace for the Helm release.
  --values <file>             : Specify your own values file for the Helm chart.
  --install-tools             : Install required tools (oc and helm) if not already installed.
  --uninstall                 : Uninstall the Helm chart and resources.
  --uninstall-all             : Uninstall all resources, including Helm chart.
  --help                      : Show this help message and exit.

Examples:
  $0 --router-base example.com --release-name myrelease --values /path/to/values.yaml
  $0 --install-tools
  $0 --uninstall --uninstall-all
"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install oc CLI
install_oc() {
    if command_exists oc; then
        echo "oc is already installed."
    else
        curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/linux/oc.tar.gz
        tar -xf oc.tar.gz
        mv oc /usr/local/bin/
        rm oc.tar.gz
        echo "oc installed successfully."
    fi
}

# Function to install Helm
install_helm() {
    if command_exists helm; then
        echo "Helm is already installed."
    else
        echo "Installing Helm 3 client"
        curl -sL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
        echo "helm client installed successfully."
    fi
}

# Function to add Helm repo
add_helm_repo() {
    if ! helm repo list | grep -q "^${HELM_REPO_NAME}"; then
        helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"
    else
        echo "Repository $HELM_REPO_NAME already exists - updating repository instead."
        helm repo update
    fi    
}

# Function to uninstall all OpenShift resources
uninstall_all_resources() {
    oc delete configmap app-config-rhdh --namespace=${NAME_SPACE}
    oc delete secret rhdh-pull-secret --namespace=${NAME_SPACE}
    oc delete secret keycloak-secrets --namespace=${NAME_SPACE}
    oc delete secret rhdh-secrets --namespace=${NAME_SPACE}
    oc delete configmap rbac-policy --namespace=${NAME_SPACE}
    oc delete deployment backstage-app --namespace=${NAME_SPACE}
    oc delete pipeline hello-world-pipeline --namespace=${NAME_SPACE}
    oc delete pipelinerun hello-world-pipeline-run --namespace=${NAME_SPACE}
    oc delete serviceaccount rhdh-k8s-plugin --namespace=${NAME_SPACE}
    oc delete secret rhdh-k8s-plugin-secret --namespace=${NAME_SPACE}
    oc delete clusterrole rhdh-k8s-plugin --namespace=${NAME_SPACE}
    oc delete clusterrole rhdh-k8s-plugin-ocm --namespace=${NAME_SPACE}
    oc delete clusterrolebinding rhdh-k8s-plugin
    oc delete clusterrolebinding rhdh-k8s-plugin-ocm
    oc delete cronjob say-hello --namespace=${NAME_SPACE}
    oc delete job print-pi --namespace=${NAME_SPACE}
    oc delete daemonset test-daemonset --namespace=${NAME_SPACE}
    oc delete statefulset example-statefulset --namespace=${NAME_SPACE}
    oc delete service example-service --namespace=${NAME_SPACE}
}

# Function to detect cluster router base
detect_cluster_router_base() {
    CLUSTER_ROUTER_BASE=$(oc get ingress.config.openshift.io/cluster -o=jsonpath='{.spec.domain}')
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --router-base)
            CLUSTER_ROUTER_BASE="$2"
            shift
            ;;
        --release-name)
            RELEASE_NAME="$2"
            shift
            ;;
        --generate-name)
            GENERATE_NAME=true
            ;;
        --namespace)
            NAME_SPACE="$2"
            shift
            ;;
        --values)
            HELM_CHART_VALUE_FILE_NAME="$2"
            shift
            ;;
        --install-tools)
            install_oc
            install_helm
            exit 0
            ;;
        --uninstall)
            helm uninstall "$RELEASE_NAME" -n "$NAME_SPACE"
            oc delete pvc data-redhat-developer-hub-postgresql-0 --namespace=${NAME_SPACE}
            oc delete pvc data-backstage-postgresql-0 --namespace=${NAME_SPACE}
            if [[ "$2" == "--all" ]]; then
                uninstall_all_resources
            fi
            exit 0
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

# Ensure required commands are available
if ! command_exists helm || ! command_exists oc; then
    echo "Error: Both 'helm' and 'oc' are required. Use --install-tools to install them."
    exit 1
fi

# Detect or set the cluster router base
if [[ -z "$CLUSTER_ROUTER_BASE" ]]; then
    detect_cluster_router_base || (echo "Error: Cluster router base could not be detected. Please provide it using the --router-base flag." && exit 1)
fi

# Create namespace and apply resources
oc new-project "${NAME_SPACE}" || oc project "${NAME_SPACE}"

# Apply resources
PWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo "$PWD"

# Update namespace in YAML files
sed -i "s/namespace:.*/namespace: $NAME_SPACE/g" $PWD/resources/service-account-rhdh.yaml
sed -i "s/namespace:.*/namespace: $NAME_SPACE/g" $PWD/resources/cluster-roles/cluster-role-binding-k8s.yaml
sed -i "s/namespace:.*/namespace: $NAME_SPACE/g" $PWD/resources/cluster-roles/cluster-role-binding-ocm.yaml

# Apply OpenShift resources
oc apply -f $PWD/resources/service-account-rhdh.yaml --namespace=${NAME_SPACE}
oc apply -f $PWD/auth/service-account-rhdh-secret.yaml --namespace=${NAME_SPACE}
oc apply -f $PWD/resources/cluster-roles/cluster-role-k8s.yaml --namespace=${NAME_SPACE}
oc apply -f $PWD/resources/cluster-roles/cluster-role-binding-k8s.yaml --namespace=${NAME_SPACE}
oc apply -f $PWD/resources/cluster-roles/cluster-role-ocm.yaml --namespace=${NAME_SPACE}
oc apply -f $PWD/resources/cluster-roles/cluster-role-binding-ocm.yaml --namespace=${NAME_SPACE}
oc apply -f $PWD/resources/pipelines/hello-world-pipeline.yaml --namespace=${NAME_SPACE}
oc apply -f $PWD/resources/pipelines/hello-world-pipeline-run.yaml --namespace=${NAME_SPACE}
oc apply -f $PWD/resources/jobs/cron-job.yaml --namespace=${NAME_SPACE}
oc apply -f $PWD/resources/jobs/pi-job.yaml --namespace=${NAME_SPACE}
oc apply -f $PWD/resources/daemon-sets/daemon-set.yaml --namespace=${NAME_SPACE}
oc apply -f $PWD/resources/deployments/backstage-test.yaml --namespace=${NAME_SPACE}
oc apply -f $PWD/resources/stateful-sets/stateful-set.yaml --namespace=${NAME_SPACE}
oc apply -f $PWD/resources/rbac-policies.yaml --namespace=${NAME_SPACE}
oc apply -f $PWD/auth/quay-pull-secret.yaml --namespace=${NAME_SPACE}
oc apply -f $PWD/auth/secrets-rhdh-secrets.yaml --namespace=${NAME_SPACE}
oc apply -f $PWD/auth/keycloak-secrets.yaml --namespace=${NAME_SPACE}

# Obtain and update Kubernetes token in secrets file
oc get secret rhdh-k8s-plugin-secret --namespace=${NAME_SPACE} -o yaml > $PWD/auth/service-account-rhdh-token.yaml
TOKEN=$(grep 'token:' $PWD/auth/service-account-rhdh-token.yaml | awk '{print $2}')
sed -i "s/K8S_CLUSTER_TOKEN:.*/K8S_CLUSTER_TOKEN: $TOKEN/g" $PWD/auth/secrets-rhdh-secrets.yaml
oc apply -f $PWD/auth/secrets-rhdh-secrets.yaml --namespace=${NAME_SPACE}

# Add Helm repo and install/upgrade Helm chart
add_helm_repo
helm upgrade -i "$RELEASE_NAME" -n "$NAME_SPACE" -f "$HELM_CHART_VALUE_FILE_NAME" rhdh-chart/backstage
