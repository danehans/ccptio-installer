#! /bin/sh
#
# Early version of an Istio Installer for CCP
#
# This file is fetched as: curl -L $URL | sh -
# so it should be pure bourne shell, not bash (and not reference other scripts).
#

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
    echo "### This script must be run as root or with sudo. For example:"
    echo "curl -L https://git.io/install-ccptio | sudo sh -"
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
  KOSEXT="darwin"
else
  OSEXT="linux"
  KOSEXT="linux"
fi

# Download Istio install templates, and sample apps.
NAME="istio-${ISTIO_VERSION}"
URL="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-${OSEXT}.tar.gz"
CHECK="$(stat ${NAME} 2> /dev/null)"
if [ "${CHECK}" ] ; then
    echo "### Istio install templates, and sample apps currently installed at ${NAME}, skipping ..."
else
    # Download Istio install templates, and sample apps.
    echo "### Downloading $NAME from $URL ..."
    curl -sL "$URL" | tar xz
    echo "### Downloaded Istio install templates, and sample apps into $NAME ..."
fi

# Download istioctl binary, Istio install templates, and sample apps.
NAME="istioctl"
ISTIOCTL="istio-${ISTIO_VERSION}/bin/${NAME}"
URL="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-${OSEXT}.tar.gz"
SUPPORTED_VERSION="$(${NAME} version 2> /dev/null | grep ${ISTIO_VERSION})"
if [ "${SUPPORTED_VERSION}" ] ; then
    echo "### ${NAME} ${ISTIO_VERSION} currently installed, skipping ..."
else
    if ! [ "$(stat ${ISTIOCTL} 2> /dev/null)" ] ; then
        echo "### Downloading ${NAME} from ${URL} ..."
        curl -sL "${URL}" | tar xz 2> /dev/null
        echo "### ${NAME} ${ISTIO_VERSION} downloaded ..."
    fi
    # Move istioctl binary to BIN_DIR
    chmod +x ${ISTIOCTL}
    mv ${ISTIOCTL} ${BIN_DIR}
    echo "### ${NAME} v${ISTIO_VERSION} binary installed at ${BIN_DIR} ..."
fi

# kubectl binary download and setup.
NAME="kubectl"
URL="https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/${KOSEXT}/amd64/kubectl"
SUPPORTED_VERSION="$(kubectl version --client --short 2> /dev/null | grep v${KUBECTL_VERSION})"
if [ "${SUPPORTED_VERSION}" ] ; then
    echo "### ${NAME} ${KUBECTL_VERSION} currently installed, skipping ..."
else
    if ! [ "$(stat ${NAME} 2> /dev/null)" ] ; then
        echo "### Downloading ${NAME} v${KUBECTL_VERSION} from ${URL} ..."
        curl -sLO "${URL}"
    fi
    # Move kubectl binary to ${BIN_DIR}
    chmod +x ./${NAME}
    mv ./${NAME} ${BIN_DIR}
    echo "### ${NAME} v${KUBECTL_VERSION} binary installed at ${BIN_DIR} ..."
fi

# helm client binary download and setup.
NAME="helm"
HELM_TARBALL="helm-v${HELM_VERSION}-${KOSEXT}-amd64.tar.gz"
URL="https://storage.googleapis.com/kubernetes-helm/${HELM_TARBALL}"
SUPPORTED_VERSION="$(helm version --client --short 2> /dev/null | grep v${HELM_VERSION})"
if [ "${SUPPORTED_VERSION}" ] ; then
    echo "### ${NAME} v${HELM_VERSION} currently installed, skipping ..."
else
    if ! [ "$(stat ${HELM_TARBALL} 2> /dev/null)" ] ; then
        echo "### Downloading ${NAME} from ${URL} ..."
        curl -sLO "${URL}"
        tar -xzvf ${HELM_TARBALL}
    fi
    # Move helm binary to ${BIN_DIR}
    chmod +x ${KOSEXT}-amd64/${NAME}
    mv ${KOSEXT}-amd64/${NAME} ${BIN_DIR}
    rm -rf ${HELM_TARBALL} ${KOSEXT}-amd64
    echo "### ${NAME} v${HELM_VERSION} binary installed at ${BIN_DIR} ..."
fi

# Render Kubernetes manifest for Istio deployment.
MANIFEST="$HOME/istio-${ISTIO_VERSION}.yaml"
if [ "$(stat ${MANIFEST} 2> /dev/null)" ]; then
    echo "### Kubernetes manifest ${MANIFEST} currently rendered, skipping ..."
    echo "### Run \"rm -rf ${MANIFEST}\" to re-render the Kubernetes manifest ..."
else
    echo "### Rendering ${MANIFEST} Kubernetes manifest for Istio deployment ..."
    helm template istio-${ISTIO_VERSION}/install/kubernetes/helm/istio \
    --set ingressgateway.service.type=NodePort \
    --name istio --namespace ${ISTIO_NAMESPACE} > ${MANIFEST}
    echo "### Rendered ${MANIFEST} Kubernetes manifest for Istio deployment ..."
fi

# Create Kubernetes namespace used for Istio.
kubectl get ns ${ISTIO_NAMESPACE} 2> /dev/null
if [ $? -eq 0 ] ; then
    echo "### ${ISTIO_NAMESPACE} namespace currently exists, skipping ..."
else
    echo "### Creating Kubernetes namespace ${ISTIO_NAMESPACE} used for Istio ..."
    kubectl create ns ${ISTIO_NAMESPACE}
fi

# Label default Kubernetes namespace for Istio automatic sidecar injection.
kubectl get namespace -L istio-injection 2> /dev/null | grep ${ISTIO_INJECT_NS} | grep enabled
if [ $? -eq 0 ] ; then
    echo "### Istio auto sidecar injection for \"${ISTIO_INJECT_NS}\" namespace currently exists, skipping ..."
else
    echo "### Labeling ${ISTIO_INJECT_NS} Kubernetes namespace for Istio automatic sidecar injection ..."
    kubectl label namespace ${ISTIO_INJECT_NS} istio-injection=enabled
fi

# Deploy Istio.
kubectl get deploy -n ${ISTIO_NAMESPACE} 2> /dev/null | grep istio-pilot
if [ $? -eq 0 ] ; then
    echo "### A Kubernetes deployment for Istio in namespace \"${ISTIO_NAMESPACE}\" currently exists, skipping deployment."
    echo "### To redeploy Istio in namespace \"${ISTIO_NAMESPACE}\", run \"kubectl delete -f ${MANIFEST}\""
    echo "### or use a different value for ISTIO_NAMESPACE."
else
    echo "### Deploying Istio using manifest ${MANIFEST} ..."
    kubectl create -f ${MANIFEST}
    echo "### Waiting ${SLEEP_TIME}-seconds for Istio pods to achieve a Running or Completed status ..."
    sleep ${SLEEP_TIME}
    kubectl get po -n ${ISTIO_NAMESPACE}
    echo "### Completed Istio deployment!"
    echo "### Use \"kubectl get po -n ${ISTIO_NAMESPACE}\" to verify all pods are in a Running or Completed status."
fi

# Install bookinfo sample app
if [ "${INSTALL_BOOKINFO}" = "true" ] ; then
    kubectl get po | grep productpage
    if [ $? -eq 0 ] ; then
        echo "### Bookinfo app exists, skipping ..."
    else
        echo "### Creating bookinfo deployment"
        kubectl create -f istio-${ISTIO_VERSION}/samples/bookinfo/kube/bookinfo.yaml
    fi
    kubectl get ing | grep gateway
    if [ $? -eq 0 ] ; then
        echo "### Bookinfo ingress exists, skipping ..."
    else
        echo "### Creating bookinfo ingress"
        kubectl create -f istio-${ISTIO_VERSION}/samples/bookinfo/kube/bookinfo-gateway.yaml
    fi
    # Test the bookinfo productpage ingress
    echo "### Waiting ${SLEEP_TIME}-seconds for bookinfo deployment to complete before testing ..."
    sleep ${SLEEP_TIME}
    NODE_IP=$(kubectl get po -l istio=ingress -n istio-system -o jsonpath='{.items[0].status.hostIP}')
    NODE_PORT=$(kubectl get svc istio-ingress -n istio-system -o jsonpath='{.spec.ports[0].nodePort}')
    echo "### Testing bookinfo productpage ingress with the following:"
    echo "### curl -I http://${NODE_IP}:${NODE_PORT}/productpage"
    echo "### Expecting \"HTTP/1.1 200 OK\" return code."
    RESP=$(curl -w %{http_code} -s -o /dev/null http://${NODE_IP}:${NODE_PORT}/productpage)
    if [ "${RESP}" = "200" ] ; then
        echo "### Bookinfo gateway test succeeeded with \"HTTP/1.1 ${RESP} OK\" return code."
        echo "### Your Istio service mesh is ready to use."
        echo "### You can remove the bookinfo sample application with the following:"
        echo "kubectl delete -f istio-${ISTIO_VERSION}/samples/bookinfo/kube/bookinfo-gateway.yaml"
        echo "kubectl delete -f istio-${ISTIO_VERSION}/samples/bookinfo/kube/bookinfo.yaml"
    else
        echo "### Bookinfo gateway test failed or timed-out."
        echo "### Expected a \"200\" http return code, received a \"${RESP}\" return code."
        echo "### Manually test with the following:"
        echo "### curl -I http://${NODE_IP}:${NODE_PORT}/productpage"
    fi
fi

