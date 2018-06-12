#! /bin/sh
#
# Early version of an Istio Uninstaller for CCP
#
# This file is fetched as: curl -L $URL | sh -
# so it should be pure bourne shell, not bash (and not reference other scripts).
#

# TODO: Remove 0.8.0 after initial testing.
export ISTIO_VERSION="${ISTIO_VERSION:-0.8.0}"
export KUBECTL_VERSION="${KUBECTL_VERSION:-1.10.1}"
export HELM_VERSION="${HELM_VERSION:-2.8.2}"
export ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
export BIN_DIR="${BIN_DIR:-/usr/local/bin}"
export ISTIO_INJECT_NS="${ISTIO_INJECT_NS:-default}"
export INSTALL_BOOKINFO="${INSTALL_BOOKINFO:-true}"
export SLEEP_TIME="${SLEEP_TIME:-30}"

# Check for Root user.
if [ "$(id -u)" != "0" ]; then
    echo "### This script must be run as root or with sudo"
    exit 1
fi

# Check for kubectl config file.
if ! [ "$(stat ${KUBECONFIG})" ] ; then
    echo "### You must store your tenant cluster credentials to ${KUBECONFIG} before running this script."
    exit 1
fi

# Set operating system to download correct binaries.
OS="$(uname)"
if [ "x${OS}" = "xDarwin" ] ; then
  OSEXT="osx"
else
  OSEXT="linux"
fi

# Download the latest version of Istio if ISTIO_VERSION is not specified.
if [ "x${ISTIO_VERSION}" = "x" ] ; then
  ISTIO_VERSION=$(curl -sL https://api.github.com/repos/istio/istio/releases/latest | \
                  grep tag_name | sed "s/ *\"tag_name\": *\"\(.*\)\",*/\1/")
fi

# Check for existence of istioctl and project directory.
ISTIOCTL_CHECK="$(istioctl version | grep ${ISTIO_VERSION})"
if [ "${ISTIOCTL_CHECK}" ] ; then
    echo "### istioctl ${ISTIO_VERSION} currently installed, continuing with clean-up ..."
else
    echo "### istioctl ${ISTIO_VERSION} not installed, exiting clean-up ..."
    exit 1
fi

# kubectl binary download and setup.
KUBECTL_CHECK="$(kubectl version --client --short | grep v${KUBECTL_VERSION})"
if [ "${KUBECTL_CHECK}" ] ; then
    echo "### kubectl ${KUBECTL_VERSION} currently installed, continuing with clean-up ..."
else
    echo "### kubectl v${KUBECTL_VERSION} not installed, exiting clean-up ..."
    exit 1
fi

# helm client binary download and setup.
HELM_CHECK="$(helm version --client --short | grep v${HELM_VERSION})"
if [ "${HELM_CHECK}" ] ; then
    echo "### helm v${HELM_VERSION} currently installed, continuing with clean-up ..."
else
    echo "### helm v${HELM_VERSION} not installed, exiting clean-up  ..."
    exit 1
fi

# Remove bookinfo sample app
if [ "${INSTALL_BOOKINFO}" = "true" ] ; then
    kubectl get po | grep productpage
    if [ $? -eq 0 ] ; then
        echo "Deleting bookinfo deployment"
        kubectl delete -f istio-${ISTIO_VERSION}/samples/bookinfo/kube/bookinfo.yaml
    fi
    kubectl get ing | grep gateway
    if [ $? -eq 0 ] ; then
        echo "Deleting bookinfo ingress"
        kubectl delete -f istio-${ISTIO_VERSION}/samples/bookinfo/kube/bookinfo-gateway.yaml
    fi
fi   


# Remove Istio control-plane deployment.
kubectl get deploy -n ${ISTIO_NAMESPACE} | grep istio-pilot
if [ $? -eq 0 ] ; then
    echo "### Deleting Kubernetes deployment for Istio in namespace \"${ISTIO_NAMESPACE}\" ..."
    kubectl delete -f $HOME/istio-${ISTIO_VERSION}.yaml
    # Wait SLEEP_TIME sec for resource to be removed from k8s.
    sleep ${SLEEP_TIME}
    echo "### Deleted Kubernetes deployment for Istio in namespace \"${ISTIO_NAMESPACE}\" ..."
else
    echo "### The Istio deployment for namespace \"${ISTIO_NAMESPACE}\" does not exist ..."
fi

# Remove ISTIO_INJECT_NS namespace label used for Istio automatic sidecar injection.
kubectl get namespace -L istio-injection | grep ${ISTIO_INJECT_NS} | grep enabled
if [ $? -eq 0 ] ; then
    echo "### Removing \"istio-injection=enabled\" from \"${ISTIO_INJECT_NS}\" namespace ..."
    kubectl label namespace ${ISTIO_INJECT_NS} istio-injection-
else
    echo "### Label \"istio-injection=enabled\" does not exist for \"${ISTIO_INJECT_NS}\", skipping ..."
fi

# Remove Kubernetes ISTIO_NAMESPACE namespace used by Istio control-plane.
kubectl get ns ${ISTIO_NAMESPACE}
if [ $? -eq 0 ] ; then
    echo "### Removing \"${ISTIO_NAMESPACE}\" namespace ..."
    kubectl delete ns ${ISTIO_NAMESPACE}
else
    echo "### Namespace \"${ISTIO_NAMESPACE}\" does not exist, skipping ..."
fi

# Render Kubernetes manifest for Istio deployment.
MANIFEST="$HOME/istio-${ISTIO_VERSION}.yaml"
if [ "$(stat ${MANIFEST})" ]; then
    echo "### Removing manifest ${MANIFEST} ..."
    rm -rf $MANIFEST
else
    echo "### Kubernetes manifest ${MANIFEST} cdoes not exist, skipping ..."
fi

# Remove helm client binary.
if [ "${HELM_CHECK}" ] ; then
    echo "### Removing helm v${HELM_VERSION} from ${BIN_DIR} ..."
    rm -rf ${BIN_DIR}/helm
else
    echo "### helm v${HELM_VERSION} not installed in ${BIN_DIR}, skipping ..."
fi

# Remove kubectl client binary.
if [ "${KUBECTL_CHECK}" ] ; then
    echo "### Removing kubectl v${KUBECTL_VERSION} from ${BIN_DIR} ..."
    rm -rf ${BIN_DIR}/kubectl
else
    echo "### kubectl v${KUBECTL_VERSION} not installed in ${BIN_DIR}, skipping ..."
fi

# Remove istioctl client binary.
if [ i"${ISTIOCTL_CHECK}" ] ; then
    echo "### Removing istioctl v${ISTIO_VERSION} from ${BIN_DIR} ..."
    rm -rf ${BIN_DIR}/istioctl
else
    echo "### istioctl v${ISTIO_VERSION} not installed in ${BIN_DIR}, skipping ..."
fi

# Remove Istio project directory
if [ "$(stat istio-${ISTIO_VERSION})" ] ; then
    echo "### Removing istio-${ISTIO_VERSION} project directory ..."
    rm -rf istio-${ISTIO_VERSION}
else
    echo "### Istio project directory \"istio-${ISTIO_VERSION}\" does not exist, skipping ..."
fi

echo "### Istio installation clean-up complete!"
