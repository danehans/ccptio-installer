#! /bin/sh
#
# Early version of an Istio Installer for CCP
#
# This file is fetched as: curl -L $URL | sh -
# so it should be pure bourne shell, not bash (and not reference other scripts).
#

export CLUSTER_CONTEXT="${CLUSTER_CONTEXT:-}"
export ISTIO_VERSION="${ISTIO_VERSION:-0.8.0}"
export KUBECTL_VERSION="${KUBECTL_VERSION:-1.10.1}"
export HELM_VERSION="${HELM_VERSION:-2.8.2}"
export ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
export INSTALL_DIR="${INSTALL_DIR:-$HOME}"
export BIN_DIR="${BIN_DIR:-/usr/local/bin}"
export ISTIO_INJECT_NS="${ISTIO_INJECT_NS:-default}"
export INSTALL_BOOKINFO="${INSTALL_BOOKINFO:-true}"
export DAILY_BUILD="${DAILY_BUILD:-false}"
export HELM_PARAMS="${HELM_PARAMS:-}"

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

# kubectl binary download and setup.
NAME="kubectl"
URL="https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/${KOSEXT}/amd64/kubectl"
VERSION="$(${NAME} version --client --short | awk '{print $3}' 2> /dev/null)"
if [ "${VERSION}" = "v${KUBECTL_VERSION}" ] ; then
    echo "### ${NAME} ${KUBECTL_VERSION} currently installed, skipping ..."
else
    echo "### Downloading ${NAME} v${KUBECTL_VERSION} from ${URL} ..."
    curl -sLO "${URL}" 2> /dev/null
    if [ $? -ne 0 ] ; then
        echo "### Failed to download ${NAME} v${KUBECTL_VERSION} from ${URL} .."
        exit 1
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

# Download istioctl binary.
NAME="istioctl"
ISTIOCTL="${ISTIO_DIR}/bin/${NAME}"
VERSION="$(${NAME} version 2> /dev/null | grep ${ISTIO_VERSION} | awk '{print $2}' 2> /dev/null)"
if [ "${VERSION}" = "${ISTIO_VERSION}" ] ; then
    echo "### ${NAME} ${ISTIO_VERSION} currently installed, skipping ..."
else
    if ! [ "$(stat ${ISTIOCTL} 2> /dev/null)" ] ; then
        echo "### Downloading ${NAME} from ${URL} ..."
        curl -sLo ${INSTALL_DIR} ${URL} | tar xz 2> /dev/null
        if [ $? -ne 0 ] ; then
            echo "### Failed to download and untar ${NAME} ${ISTIO_VERSION} ..."
            exit 1
        fi
    fi
    echo "### ${NAME} ${ISTIO_VERSION} downloaded to ${INSTALL_DIR} ..."
    # Move istioctl binary to BIN_DIR
    chmod +x ${ISTIOCTL}
    mv ${ISTIOCTL} ${BIN_DIR}
    echo "### ${NAME} v${ISTIO_VERSION} binary installed at ${BIN_DIR} ..."
fi

# helm client binary download and setup.
NAME="helm"
HELM_TARBALL="helm-v${HELM_VERSION}-${KOSEXT}-amd64.tar.gz"
URL="https://storage.googleapis.com/kubernetes-helm/${HELM_TARBALL}"
VERSION="$(${NAME} version --client --short | grep v${HELM_VERSION} | awk '{print $2}' | cut -d + -f 1)"
if [ "${VERSION}" = "v${HELM_VERSION}" ] ; then
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
    echo "### Run \"rm -rf ${ISTIO_MANIFEST}\" to re-render the Kubernetes manifest ..."
fi

ccp_params="--set ingressgateway.service.type=NodePort --set galley.enabled=true"

helm template ${ISTIO_DIR}/install/kubernetes/helm/istio $ccp_params ${HELM_PARAMS} \
--name istio --namespace ${ISTIO_NAMESPACE} > ${ISTIO_MANIFEST}
if [ $? -eq 0 ] ; then
    echo "### Using Helm parameters: \"$ccp_params ${HELM_PARAMS}\" for Istio deployment ..."
    echo "### Rendered ${ISTIO_MANIFEST} Kubernetes manifest for Istio deployment ..."
else
    echo "### Failed to render ${ISTIO_MANIFEST} Kubernetes manifest for Istio deployment ..."
    exit 1
fi

# Create Kubernetes namespace used for Istio.
kubectl get ns ${ISTIO_NAMESPACE} 2> /dev/null
if [ $? -eq 0 ] ; then
    echo "### ${ISTIO_NAMESPACE} namespace currently exists, skipping ..."
else
    kubectl create ns ${ISTIO_NAMESPACE}
    if [ $? -ne 0 ] ; then
        echo "### Failed to create Kubernetes namespace ${ISTIO_NAMESPACE} used for Istio ..."
        exit 1
    fi
    echo "### Created Kubernetes namespace ${ISTIO_NAMESPACE} used for Istio ..."
fi

# Label default Kubernetes namespace for Istio automatic sidecar injection.
kubectl get namespace -L istio-injection 2> /dev/null | grep ${ISTIO_INJECT_NS} | grep enabled
if [ $? -eq 0 ] ; then
    echo "### Istio auto sidecar injection for \"${ISTIO_INJECT_NS}\" namespace currently exists, skipping ..."
else
    kubectl label namespace ${ISTIO_INJECT_NS} istio-injection=enabled
    if [ $? -ne 0 ] ; then
        echo "### Failed to label ${ISTIO_INJECT_NS} Kubernetes namespace for Istio automatic sidecar injection ..."
        exit 1
    fi
    echo "### Labeled ${ISTIO_INJECT_NS} Kubernetes namespace for Istio automatic sidecar injection ..."
fi

# Deploy Istio.
kubectl get deploy -n ${ISTIO_NAMESPACE} 2> /dev/null | grep istio-pilot
if [ $? -eq 0 ] ; then
    echo "### A Kubernetes deployment for Istio in namespace \"${ISTIO_NAMESPACE}\" currently exists, skipping deployment."
    echo "### To redeploy Istio in namespace \"${ISTIO_NAMESPACE}\", run \"kubectl delete -f ${ISTIO_MANIFEST}\""
    echo "### or use a different value for ISTIO_NAMESPACE."
else
    echo "### Deploying Istio using manifest ${ISTIO_MANIFEST} ..."
    kubectl create -f ${ISTIO_MANIFEST}
    if [ $? -ne 0 ] ; then
        echo "### Failed to deploy Istio using manifest ${ISTIO_MANIFEST} ..."
        exit 1
    else
        echo "### Waiting for Istio pods to achieve a Running or Completed status ..."
        n=0
        until [ $n -ge 50 ]
        do
            kubectl get po -n ${ISTIO_NAMESPACE} && break
            n=$[$n+1]
            sleep 5
        done
        echo "### Completed Istio deployment!"
        echo "### Use \"kubectl get po -n ${ISTIO_NAMESPACE}\" to verify all pods are in a Running or Completed status."
    fi
fi

# Install bookinfo sample app
if [ "${INSTALL_BOOKINFO}" = "true" ] ; then
    if [ "${DAILY_BUILD}" = "true" ] ; then
        JSON_PATH='{.spec.ports[?(@.name=="http2")].nodePort}'
    else
        JSON_PATH='{.spec.ports[?(@.name=="http")].nodePort}'
    fi
    kubectl get po | grep productpage
    if [ $? -eq 0 ] ; then
        echo "### Bookinfo app exists, skipping ..."
    else
        echo "### Creating bookinfo deployment ..."
        echo "### Sleeping 2-minutes due to k8s issue #62725 ..."
        sleep 120
        kubectl create -f ${ISTIO_DIR}/samples/bookinfo/kube/bookinfo.yaml
        if [ $? -ne 0 ] ; then
            echo "### Failed to create bookinfo deployment ..."
            exit 1
        fi
    fi
    kubectl get ing | grep gateway
    if [ $? -eq 0 ] ; then
        NODE_IP=$(kubectl get po -l istio=ingress -n ${ISTIO_NAMESPACE} -o jsonpath='{.items[0].status.hostIP}')
        NODE_PORT=$(kubectl -n ${ISTIO_NAMESPACE} get service istio-ingressgateway -o jsonpath=${JSON_PATH})
        echo "### Bookinfo ingress gateway exists, skipping ..."
        echo "### Manually test with the following:"
        echo "### curl -I http://${NODE_IP}:${NODE_PORT}/productpage"
    else
        echo "### Creating bookinfo ingress gateway ..."
        sleep 30
        kubectl create -f ${ISTIO_DIR}/samples/bookinfo/routing/bookinfo-gateway.yaml
        if [ $? -ne 0 ] ; then
            echo "### Failed to create bookinfo ingress gateway ..."
            exit 1
        fi
        # Test the bookinfo productpage ingress
        echo "### Waiting for bookinfo deployment to complete before testing ..."
        n=0
        until [ $n -ge 50 ]
        do
            NODE_IP=$(kubectl get po -l istio=ingress -n ${ISTIO_NAMESPACE} -o jsonpath='{.items[0].status.hostIP}')
            NODE_PORT=$(kubectl -n ${ISTIO_NAMESPACE} get service istio-ingressgateway -o jsonpath=${JSON_PATH}) && break
            n=$[$n+1]
            sleep 5
        done
        echo "### bookinfo deployment complete ..."
        echo "### Testing bookinfo productpage ingress with the following:"
        echo "### curl -I http://${NODE_IP}:${NODE_PORT}/productpage"
        echo "### Expecting \"HTTP/1.1 200 OK\" return code."
        n=0
        while [ $n -le 50 ]
        do
            RESP=$(curl -w %{http_code} -s -o /dev/null http://${NODE_IP}:${NODE_PORT}/productpage)
            if [ "${RESP}" = "200" ] ; then
                echo "### Bookinfo gateway test succeeeded with \"HTTP/1.1 ${RESP} OK\" return code."
                echo "### Your Istio service mesh is ready to use."
                echo "### You can remove the bookinfo sample application with the following:"
                echo "kubectl delete -f ${ISTIO_DIR}/samples/bookinfo/kube/bookinfo-gateway.yaml"
                echo "kubectl delete -f ${ISTIO_DIR}/samples/bookinfo/kube/bookinfo.yaml"
                exit 0
            fi
            echo "testing ..."
            sleep 5
            n=`expr $n + 1`
        done
        echo "### Bookinfo gateway test timed-out."
        echo "### Expected a \"200\" http return code, received a \"${RESP}\" return code."
        echo "### Manually test with the following:"
        echo "### curl -I http://${NODE_IP}:${NODE_PORT}/productpage"
        exit 1
    fi
fi
