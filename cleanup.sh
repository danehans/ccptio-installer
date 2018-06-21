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
export SLEEP_TIME="${SLEEP_TIME:-60}"
export REMOVE_BINS="${REMOVE_BINS:-false}"

# Check for Root user.
if [ "$(id -u)" != "0" ]; then
    echo "### This script must be run as root or with sudo. For example:"
    echo "curl -L https://git.io/uninstall-ccptio | sudo sh -"
    exit 1
fi

# Check for kubectl config file.
if ! [ "$(stat ${KUBECONFIG} 2> /dev/null)" ] ; then
    echo "### You must store your tenant cluster credentials to ${KUBECONFIG} before running this script."
    exit 1
fi

# Set operating system to download correct binaries.
OS="$(uname)"
if [ "x${OS}" = "xDarwin" ] ; then
  OSEXT="osx"
  KOSEXT="darwin"
else
  OSEXT="linux"
  KOSEXT="linux"
fi

# Download Istio install templates, and sample apps.
NAME="istio-${ISTIO_VERSION}"
URL="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-${OSEXT}.tar.gz"
CHECK="$(stat ${HOME}/${NAME} 2> /dev/null)"
if [ "${CHECK}" ] ; then
    echo "### Istio install templates and sample apps currently installed at ${HOME}/${NAME}, skipping ..."
else
    # Download Istio install templates, and sample apps.
    echo "### Downloading ${NAME} from ${URL} ..."
    curl -sL ${URL} | tar xz
    if [ $? -ne 0 ] ; then
        echo "### Failed to download and untar Istio install templates and sample apps ... "
        exit 1
    fi
    mv ${NAME} ${HOME}/${CLUSTER}-${NAME}
    if [ $? -ne 0 ] ; then
        echo "### Failed to move \"${NAME}\" to \"${HOME}/${CLUSTER}-${NAME}\" ... "
        exit 1
    fi
    echo "### Downloaded Istio install templates and sample apps to ${HOME}/${CLUSTER}-${NAME} ..."
fi

# kubectl binary download and setup.
KUBECTL_CHECK="$(kubectl version --client --short 2> /dev/null | grep v${KUBECTL_VERSION})"
if [ "${KUBECTL_CHECK}" ] ; then
    echo "### kubectl v${KUBECTL_VERSION} currently installed, continuing with clean-up ..."
else
    echo "### kubectl v${KUBECTL_VERSION} is required for clean-up, installing kubectl ..."
    # kubectl binary download and setup.
    NAME="kubectl"
    URL="https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/${KOSEXT}/amd64/kubectl"
    if ! [ "$(stat ${NAME} 2> /dev/null)" ] ; then
        echo "### Downloading ${NAME} v${KUBECTL_VERSION} from ${URL} ..."
        curl -sLO "${URL}"
    fi
    # Move kubectl binary to ${BIN_DIR}
    chmod +x ./${NAME}
    mv ./${NAME} ${BIN_DIR}
    echo "### ${NAME} v${KUBECTL_VERSION} binary installed at ${BIN_DIR} ..."
fi

# Remove bookinfo sample app
if [ "${INSTALL_BOOKINFO}" = "true" ] ; then
    kubectl get po 2> /dev/null | grep productpage
    if [ $? -eq 0 ] ; then
        echo "Deleting bookinfo deployment"
        kubectl delete -f istio-${ISTIO_VERSION}/samples/bookinfo/kube/bookinfo.yaml
    fi
    kubectl get ing 2> /dev/null | grep gateway
    if [ $? -eq 0 ] ; then
        echo "Deleting bookinfo ingress"
        kubectl delete -f istio-${ISTIO_VERSION}/samples/bookinfo/kube/bookinfo-gateway.yaml
    fi
fi   

# Remove Istio deployment.
kubectl get deploy -n ${ISTIO_NAMESPACE} 2> /dev/null | grep istio-pilot
if [ $? -eq 0 ] ; then
    echo "### Deleting Istio deployment in namespace \"${ISTIO_NAMESPACE}\" ..."
    kubectl delete -f $HOME/istio-${ISTIO_VERSION}.yaml
    if [ $? -ne 0 ] ; then
        echo "### Failed to delete Istio deployment in namespace \"${ISTIO_NAMESPACE}\" ..."
        exit 1
    fi
    # Wait SLEEP_TIME sec for resource to be removed from k8s.
    sleep ${SLEEP_TIME}
    echo "### Deleted Kubernetes deployment for Istio in namespace \"${ISTIO_NAMESPACE}\" ..."
else
    echo "### The Istio deployment for namespace \"${ISTIO_NAMESPACE}\" does not exist ..."
fi

# Remove ISTIO_INJECT_NS namespace label used for Istio automatic sidecar injection.
kubectl get namespace -L istio-injection 2> /dev/null | grep ${ISTIO_INJECT_NS} | grep enabled
if [ $? -eq 0 ] ; then
    echo "### Removing \"istio-injection=enabled\" from \"${ISTIO_INJECT_NS}\" namespace ..."
    kubectl label namespace ${ISTIO_INJECT_NS} istio-injection-
    if [ $? -ne 0 ] ; then
        echo "### Failed to remove \"istio-injection=enabled\" from \"${ISTIO_INJECT_NS}\" namespace ..."
        exit 1
    fi
else
    echo "### Label \"istio-injection=enabled\" does not exist for \"${ISTIO_INJECT_NS}\", skipping ..."
fi

# Remove Kubernetes ISTIO_NAMESPACE namespace used by Istio.
kubectl get ns ${ISTIO_NAMESPACE} 2> /dev/null
if [ $? -eq 0 ] ; then
    echo "### Removing \"${ISTIO_NAMESPACE}\" namespace ..."
    kubectl delete ns ${ISTIO_NAMESPACE}
    if [ $? -ne 0 ] ; then
        echo "### Failed to remove \"${ISTIO_NAMESPACE}\" namespace ..."
        exit 1
    fi
else
    echo "### Namespace \"${ISTIO_NAMESPACE}\" does not exist, skipping ..."
fi

# Remove Kubernetes manifest for Istio deployment.
MANIFEST="$HOME/istio-${ISTIO_VERSION}.yaml"
if [ "$(stat ${MANIFEST} 2> /dev/null)" ]; then
    echo "### Removing manifest ${MANIFEST} ..."
    rm -rf $MANIFEST
else
    echo "### Kubernetes manifest ${MANIFEST} does not exist, skipping ..."
fi

# Remove Istio project directory
if [ "$(stat istio-${ISTIO_VERSION} 2> /dev/null)" ] ; then
    echo "### Removing istio-${ISTIO_VERSION} project directory ..."
    rm -rf istio-${ISTIO_VERSION}
else
    echo "### Istio project directory \"istio-${ISTIO_VERSION}\" does not exist, skipping ..."
fi

# Remove binaries.
if [ "${REMOVE_BINS}" = "true" ] ; then
    # Remove helm client binary.
    HELM_CHECK="$(helm version --client --short 2> /dev/null | grep v${HELM_VERSION})"
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
    ISTIOCTL_CHECK="$(istioctl version 2> /dev/null | grep ${ISTIO_VERSION})"
    if [ "${ISTIOCTL_CHECK}" ] ; then
        echo "### Removing istioctl v${ISTIO_VERSION} from ${BIN_DIR} ..."
        rm -rf ${BIN_DIR}/istioctl
    else
        echo "### istioctl v${ISTIO_VERSION} not installed in ${BIN_DIR}, skipping ..."
    fi
fi

echo "### Istio clean-up complete!"
