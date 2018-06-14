# ccptio-installer
Istio Installation Script for Cisco Container Platform (CCP)

## Table of Contents

   1. [Prerequisites](#prerequisites)
   2. [Istio Deployment](#istio-deployment)
   3. [Sample Application Deployment](#sample-application-deployment)
   4. [Troubleshooting](#troubleshooting)
   5. [Istio Cleanup](#istio-cleanup)

## Prerequisites

The following prerequisites must be met before using ccptio-installer:

1. CCP installed and a tenant cluster created according to the [CCP Installation Guide](https://www.cisco.com/c/en/us/td/docs/net_mgmt/cisco_container_platform/1-0/Installation_Guide/CCP-Installation-Guide-01/CCP-Installation-Guide-01_chapter_00.html)
2. CCP tenant cluster credentials. Use the [CCP Installation Guide](https://www.cisco.com/c/en/us/td/docs/net_mgmt/cisco_container_platform/1-0/Installation_Guide/CCP-Installation-Guide-01/CCP-Installation-Guide-01_chapter_00.html) to generate and download the cluster credentials.
3. Root or sudo access on the system that ccptio-installer will be run from.

## Istio Deployment

Deploying Istio to CCP requires one command:
```
curl -L https://git.io/install-ccptio  | sh -
```

Several environment variables that can be used to customize the deployment. Review the
[installation script](https://github.com/danehans/ccptio-installer/blob/master/install.sh) for details.

## Customizing the Installation

Environment variables can be used to customize the installation. Review the
[installer](https://github.com/danehans/ccptio-installer/blob/master/install.sh) to learn more about the
supported options. Setting options take the form of:
```bash
export OPTION=VALUE
```

For example, to change the Kubernetes namespace used to install Istio:
```bash
export ISTIO_NAMESPACE=ccptio
```

Now when you run the installer, Istio will be installed in the `ccptio` namespace instead of the default (istio-system).

## Sample Application Deployment

By default, ccptio-installer deploys and tests the bookinfo sample application. You can set `INSTALL_BOOKINFO` to `false to
not deploy and test the bookinfo sample applicstion:
```
export INSTALL_BOOKINFO="false"
```

The bookinfo application exposes the `productpage` service externally using a `NodePort`. This means the service can
be accessed using `$NODE_IP:$NODE_PORT/$INGRESS_PATH`, where `$NODE_IP` is an IP address of any worker node in the tenant
cluster, $NODE_PORT is the `nodePort` value of the `istio-ingress` service and $PATH is the backend path of the bookinfo
`gateway` Ingress resource.

If you would like to manually test the bookinfo app, set the environment variables used to construct the bookinfo
productpage URL:
```
export NODE_IP=$(kubectl get po -l istio=ingress -n istio-system -o jsonpath='{.items[0].status.hostIP}')
export NODE_PORT=$(kubectl get svc istio-ingress -n istio-system -o jsonpath='{.spec.ports[0].nodePort}')
```

Use curl to test connectivity to the `productpage` Ingress:
```
curl -I http://$NODE_IP:$NODE_PORT/productpage
```

Verify that you receive a `200` response code:
```
HTTP/1.1 200 OK
content-type: text/html; charset=utf-8
content-length: 4083
server: envoy
date: Tue, 05 Jun 2018 18:44:33 GMT
x-envoy-upstream-service-time: 6024
```

You have successfully deployed the bookinfo application.

## Istio Cleanup

Removing everything done by the ccptio-installer script requires one command:
```
curl -L https://git.io/uninstall-ccptio  | sh -
```
Several environment variables that can be used to customize the cleanup. Review the
[cleanup script](https://github.com/danehans/ccptio-installer/blob/master/cleanup.sh) for details.

## Troubleshooting

stio Client installation by using the `istioctl version` command. You should receive output similar to the
following:
```
Version: 0.8.0
GitRevision: 6f9f420f0c7119ff4fa6a1966a6f6d89b1b4db84
User: root@48d5ddfd72da
Hub: docker.io/istio
GolangVersion: go1.10.1
BuildStatus: Clean
```

Verify the Helm installation by using the `helm version` command. You should receive output similar to the following:
```
Client: &version.Version{SemVer:"v2.8.2", GitCommit:"<SNIP>", GitTreeState:"clean"}
<SNIP>
```

Verify the Kubernetes Client installation by using the `kubectl version --client --short` command. You should receive
output similar to the following:
```
Client Version: v1.10.1
```

Verify that you can access the Kubernetes API with the `kubectl cluster-info` command. You should receive output
similar to the following::
```bash
Kubernetes master is running at https://$KUBE_API_HOST:$KUBE_API_PORT
Elasticsearch is running at https://$KUBE_API_HOST:$KUBE_API_PORT/api/v1/namespaces/kube-system/services/elasticsearch-logging/proxy
Kibana is running at https://$KUBE_API_HOST:$KUBE_API_PORT/api/v1/namespaces/kube-system/services/kibana-logging/proxy
KubeDNS is running at https://$KUBE_API_HOST:$KUBE_API_PORT/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

Verify your Kubernetes client configuration with the `kubectl config view` command. You should receive output similar to
the following::
```bash
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: REDACTED
    server: https://10.1.1.14:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: kubernetes-admin
  name: kubernetes-admin@kubernetes
current-context: kubernetes-admin@kubernetes
kind: Config
preferences: {}
users:
- name: kubernetes-admin
  user:
    client-certificate-data: REDACTED
```

If Istio pods do not achieve a `Completed` or `Running` status, inspect the container logs:

```
kubectl logs $POD_NAME -n istio-system -c $CONTAINER_NAME
```
__Note__: You can obtain $POD_NAME from the `kubectl get po -n istio-system` command and $CONTAINER_NAME from the
`kubectl get po/$POD_NAME -o yaml` command.

Use the official Istio [troubleshooting](https://istio.io/help/troubleshooting/) for additional troubleshooting support.
