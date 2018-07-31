#! /bin/sh
#
# Early version of an Istio Uninstaller for CCP
#
# This file is fetched as: curl -L $URL | sh -
# so it should be pure bourne shell, not bash (and not reference other scripts).
#

export CLUSTER_CONTEXT="${CLUSTER_CONTEXT:-}"
export ISTIO_VERSION="${ISTIO_VERSION:-1.0.0}"
export KUBECTL_VERSION="${KUBECTL_VERSION:-1.10.1}"
export HELM_VERSION="${HELM_VERSION:-2.8.2}"
export ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
export INSTALL_DIR="${INSTALL_DIR:-$HOME}"
export BIN_DIR="${BIN_DIR:-/usr/local/bin}"
export ISTIO_INJECT_NS="${ISTIO_INJECT_NS:-default}"
export INSTALL_BOOKINFO="${INSTALL_BOOKINFO:-true}"
export REMOVE_BINS="${REMOVE_BINS:-false}"
export DAILY_BUILD="${DAILY_BUILD:-false}"

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

# Set CLUSTER_CONTEXT environment variable if not done by user.
if [ "x${CLUSTER_CONTEXT}" = "x" ] ; then
    CLUSTER_CONTEXT=$(grep "current-context" $KUBECONFIG | awk '{print $2}' 2> /dev/null)
    if [ $? -ne 0 ] ; then
      echo "### Failed to set the Kubernetes cluster context to \"${CLUSTER_CONTEXT}\" ..."
      exit 1
    fi
    echo "### The Kubernetes cluster context has been set to \"${CLUSTER_CONTEXT}\" ..."
else
   kubectl config use-context ${CLUSTER_CONTEXT} 2> /dev/null
    if [ $? -ne 0 ] ; then
        echo "### Failed to set the Kubernetes cluster context to \"${CLUSTER_CONTEXT}\" ..."
        exit 1
    fi
    echo "### The Kubernetes cluster context has been set to \"${CLUSTER_CONTEXT}\" ..."
fi

# Create the manifest directory
INSTALL_DIR=${INSTALL_DIR}/${CLUSTER_CONTEXT}
echo "### Using \"${INSTALL_DIR}\" as the installation directory ..."
mkdir -p ${INSTALL_DIR}

# Set Istio directory and URL
if [ "${DAILY_BUILD}" = "true" ] ; then
    ISTIO_DIR="${INSTALL_DIR}/istio-release-${ISTIO_VERSION}"
    URL="https://storage.googleapis.com/istio-prerelease/daily-build/release-${ISTIO_VERSION}/istio-release-${ISTIO_VERSION}-${OSEXT}.tar.gz"
else
    ISTIO_DIR="${INSTALL_DIR}/istio-${ISTIO_VERSION}"
    URL="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-${OSEXT}.tar.gz"
fi

# Download Istio install templates, and sample apps.
DIR_CHECK="$(stat ${ISTIO_DIR} 2> /dev/null)"
if [ "${DIR_CHECK}" ] ; then
    echo "### Istio install templates and sample apps currently installed at \"${ISTIO_DIR}\", skipping ..."
else
    # Download Istio install templates, and sample apps.
    echo "### Downloading Istio install templates and sample apps to ${ISTIO_DIR} from ${URL} ..."
    curl -sL ${URL} | tar xz -C ${INSTALL_DIR} 2> /dev/null
    if [ $? -ne 0 ] ; then
        echo "### Failed to download and untar Istio install templates and sample apps ... "
        exit 1
    fi
    echo "### Downloaded Istio install templates and sample apps to ${ISTIO_DIR} ..."
fi

# helm client binary download and setup.
NAME="helm"
HELM_TARBALL="helm-v${HELM_VERSION}-${KOSEXT}-amd64.tar.gz"
URL="https://storage.googleapis.com/kubernetes-helm/${HELM_TARBALL}"
SUPPORTED_VERSION="$(helm version --client --short 2> /dev/null | grep v${HELM_VERSION})"
if [ "${SUPPORTED_VERSION}" ] ; then
    echo "### ${NAME} v${HELM_VERSION} currently installed, skipping ..."
else
    echo "### Downloading ${NAME} from ${URL} ..."
    curl -sLO "${URL}" && tar xzf ${HELM_TARBALL}
    if [ $? -ne 0 ] ; then
        echo "### Failed to download and untar ${NAME} v${HELM_VERSION} from ${URL} ..."
        exit 1
    fi
    echo "### Downloaded ${NAME} v${HELM_VERSION} from ${URL} ..."
    # Move helm binary to ${BIN_DIR}
    chmod +x ${KOSEXT}-amd64/${NAME}
    mv ${KOSEXT}-amd64/${NAME} ${BIN_DIR}
    rm -rf ${HELM_TARBALL} ${KOSEXT}-amd64
    echo "### ${NAME} v${HELM_VERSION} binary installed at ${BIN_DIR} ..."
fi

# Render Kubernetes manifest for Istio deployment.
ISTIO_MANIFEST="${ISTIO_DIR}/istio.yaml"
if [ "$(stat ${ISTIO_MANIFEST} 2> /dev/null)" ]; then
    echo "### Kubernetes manifest ${ISTIO_MANIFEST} currently rendered, skipping ..."
else
    echo "### Rendering ${ISTIO_MANIFEST} Kubernetes manifest for Istio deployment ..."
    helm template ${ISTIO_DIR}/install/kubernetes/helm/istio \
    --set ingressgateway.service.type=NodePort \
    --name istio --namespace ${ISTIO_NAMESPACE} > ${ISTIO_MANIFEST}
    if [ $? -eq 0 ] ; then
        echo "### Rendered ${ISTIO_MANIFEST} Kubernetes manifest for Istio deployment ..."
    else
        echo "### Failed to render ${ISTIO_MANIFEST} Kubernetes manifest for Istio deployment ..."
        exit 1
    fi
fi

# Remove bookinfo sample app
if [ "${INSTALL_BOOKINFO}" = "true" ] ; then
    if [ "${ISTIO_VERSION}" = "0.8.0" ]; then
        BOOKINFO_YAML="samples/bookinfo/kube/bookinfo.yaml"
        BOOKINFO_GW_YAML="samples/bookinfo/routing/bookinfo-gateway.yaml"
        RESOURCE="ing"
        GREP_KEY="gateway"
    else
        BOOKINFO_YAML="samples/bookinfo/platform/kube/bookinfo.yaml"
        BOOKINFO_GW_YAML="samples/bookinfo/networking/bookinfo-gateway.yaml"
        RESOURCE="gateways"
        GREP_KEY="bookinfo-gateway"
    fi
    kubectl get $RESOURCE 2> /dev/null | grep $GREP_KEY
    if [ $? -eq 0 ] ; then
        echo "### Deleting bookinfo ingress gateway ..."
        kubectl delete -f ${ISTIO_DIR}/${BOOKINFO_GW_YAML}
    fi
    kubectl get po 2> /dev/null | grep productpage
    if [ $? -eq 0 ] ; then
        echo "### Deleting bookinfo deployment ..."
        kubectl delete -f ${ISTIO_DIR}/${BOOKINFO_YAML}
    fi
fi   

# Remove Istio deployment.
kubectl get deploy -n ${ISTIO_NAMESPACE} 2> /dev/null | grep istio-pilot
if [ $? -eq 0 ] ; then
    if [ "${ISTIO_VERSION}" != "0.8.0" ]; then
        echo "### Deleteing Istio’s Custom Resource Definitions ..."
        kubectl delete -f ${ISTIO_DIR}/install/kubernetes/helm/istio/templates/crds.yaml -n ${ISTIO_NAMESPACE}
        echo "### Waiting 30-seconds for CRDs to be decommitted in the kube-apiserver"
        sleep 30
    fi
    echo "### Deleting Istio deployment in namespace \"${ISTIO_NAMESPACE}\" ..."
    kubectl delete -f ${ISTIO_MANIFEST}
    if [ $? -ne 0 ] ; then
        echo "### It is safe to ignore errors for non-existent resources"
        echo "### because they may have been deleted hierarchically."
    fi
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

# Remove installation directory
if [ "$(stat ${INSTALL_DIR} 2> /dev/null)" ] ; then
    echo "### Removing \"${INSTALL_DIR}\" installation directory ..."
    rm -rf ${INSTALL_DIR}
else
    echo "### Installation directory \"${INSTALL_DIR}\" does not exist, skipping ..."
fi

# Remove binaries.
if [ "${REMOVE_BINS}" = "true" ] ; then
    # Remove helm client binary.
    NAME="helm"
    VERSION="$(${NAME} version --client --short | grep v${HELM_VERSION} | awk '{print $2}' | cut -d + -f 1)"
    if [ "${VERSION}" = "v${HELM_VERSION}" ] ; then
        echo "### Removing helm v${HELM_VERSION} from ${BIN_DIR} ..."
        rm -rf ${BIN_DIR}/helm
    else
        echo "### helm v${HELM_VERSION} not installed in ${BIN_DIR}, skipping ..."
    fi
    # Remove kubectl client binary.
    NAME="kubectl"
    VERSION="$(${NAME} version --client --short | awk '{print $3}' 2> /dev/null)"
    if [ "${VERSION}" = "v${KUBECTL_VERSION}" ] ; then
        echo "### Removing kubectl v${KUBECTL_VERSION} from ${BIN_DIR} ..."
        rm -rf ${BIN_DIR}/kubectl
    else
        echo "### kubectl v${KUBECTL_VERSION} not installed in ${BIN_DIR}, skipping ..."
    fi
    # Remove istioctl client binary.
    NAME="istioctl"
    VERSION="$(${NAME} version 2> /dev/null | grep ${ISTIO_VERSION} | awk '{print $2}' 2> /dev/null)"
    if [ "${VERSION}" = "${ISTIO_VERSION}" ] ; then
        echo "### Removing istioctl v${ISTIO_VERSION} from ${BIN_DIR} ..."
        rm -rf ${BIN_DIR}/istioctl
    else
        echo "### istioctl v${ISTIO_VERSION} not installed in ${BIN_DIR}, skipping ..."
    fi
fi

echo "### Istio clean-up complete!"
