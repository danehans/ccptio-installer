# ccptio-installer
ccptio-installer is a tool for installing or removing Istio on the Cisco Container Platform (CCP).

## Introduction

[Istio](https://istio.io/) is an open platform to connect, manage, and secure microservices. This guide provides
instructions for installing and uninstalling Istio 1.0.0 or a
[daily build](https://gcsweb.istio.io/gcs/istio-prerelease/daily-build) on Cisco Container Platform (CCP) 1.0.1.
Reference the [official documentation](https://istio.io/docs/) to learn more about Istio.

## Prerequisites

The following prerequisites must be met before installing Istio on CCP:

1. CCP installed with the Calico network plugin.
2. A tenant cluster created according to the
[CCP Installation Guide](https://www.cisco.com/c/en/us/td/docs/net_mgmt/cisco_container_platform/1-0/Installation_Guide/CCP-Installation-Guide-01/CCP-Installation-Guide-01_chapter_00.html).
Tenant cluster nodes should be provisioned with at least 4 vCPUs and 24 GB of RAM.
2. CCP tenant cluster credentials (i.e. kubeconfig). Use the
[CCP User Guide](https://www.cisco.com/c/en/us/td/docs/net_mgmt/cisco_container_platform/1-0/User_Guide/CCP-User-Guide-01/CCP-User-Guide-01_chapter_0110.html#id_66394)
to download your tenant cluster credentials. The credential file should be stored at `$HOME/.kube/config` or set a
custom location:
   ```
   export KUBECONFIG=/path/to/my/config
   ```
3. Root user or `sudo` access on the system that will be used for the installation.

## Istio Installation

Installing Istio to CCP requires one command:
```bash
curl -L https://git.io/install-ccptio  | sh -
```

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

When you run the ccptio-installer, Istio will be installed in the `ccptio` namespace instead of the default
(istio-system).

ccptio-installer also supports customizing the installation through [Helm parameters](https://istio.io/docs/setup/kubernetes/helm-install/#customization-with-helm)
by using the `HELM_PARAMS` environment variable. Here is an example of setting mTLS between Istio mesh services and
setting mTLS between control-plane services through the `global.controlPlaneSecurityEnabled` and `global.mtls.enabled`
Helm parameters:
```bash
curl -L https://git.io/install-ccptio  | HELM_PARAMS="--set global.mtls.enabled=true --set global.controlPlaneSecurityEnabled=true" sh -
```

## Using Istio Daily Builds

ccptio-installer supports installing Istio from [daily builds](https://gcsweb.istio.io/gcs/istio-prerelease/daily-build)
by setting `DAILY_BUILD=true` and `ISTIO_VERSION` to the daily build version. Let's use the
[1.0-20180709-09-15](https://gcsweb.istio.io/gcs/istio-prerelease/daily-build/release-1.0-20180709-09-15/) release for
example. First, set the environment variables:
```bash
export DAILY_BUILD=true
export ISTIO_VERSION=1.0-20180709-09-15
```

Next, run ccptio-installer:
```bash
curl -L https://git.io/install-ccptio  | sh -
```

## Working with Multiple Clusters

ccptio-installer supports
[multiple Kubernetes clusters](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/)
by using the `CLUSTER_CONTEXT` environment variable. `CLUSTER_CONTEXT` is empty by default, causing ccptio-installer to
use the current cluster context. To run ccptio-installer against another cluster context, set `CLUSTER_CONTEXT` to the
name of the desired cluster context and run the installer. For example:
```bash
kubectl config get-contexts
CURRENT   NAME              CLUSTER    AUTHINFO   NAMESPACE
          admin1@cluster1   cluster1   admin1
*         admin2@cluster2   cluster2   admin2

export CLUSTER_CONTEXT=admin1@cluster1
curl -L https://git.io/install-ccptio  | sh -
```

## Sample Application Deployment

By default, the [bookinfo](https://istio.io/docs/guides/bookinfo/) sample application is included in the installation.
Set `INSTALL_BOOKINFO=false` to avoid this default behavior:
```
export INSTALL_BOOKINFO="false"
```

The bookinfo application exposes the `productpage` service externally using a `NodePort`. This means the service can
be accessed using `$NODE_IP:$NODE_PORT/$INGRESS_PATH`, where `$NODE_IP` is an IP address of any worker node in the
tenant cluster, `$NODE_PORT` is the `nodePort` value of the `istio-ingress` service and $PATH is the backend path of the
bookinfo `gateway` Ingress resource.

If you would like to manually test bookinfo, set the environment variables used to construct the productpage URL:
```
export NODE_IP=$(kubectl get po -l istio=ingress -n istio-system -o jsonpath='{.items[0].status.hostIP}')
export NODE_PORT=$(kubectl get svc istio-ingress -n istio-system -o jsonpath='{.spec.ports[0].nodePort}')
```

Use `curl` to test access to the productpage Ingress:
```
curl -I http://$NODE_IP:$NODE_PORT/productpage
```

You should receive a `HTTP/1.1 200 OK` response code:
```
HTTP/1.1 200 OK
content-type: text/html; charset=utf-8
content-length: 4083
server: envoy
date: Tue, 05 Jun 2018 18:44:33 GMT
x-envoy-upstream-service-time: 6024
```

You have successfully tested the bookinfo application on your Istio service mesh.

## Uninstall Istio

Removing everything done by the installer requires one command:
```
curl -L https://git.io/uninstall-ccptio  | sh -
```
By default, the uninstaller does not remove the istioctl, helm, and kubectl binaries. Set `REMOVE_BINS=true` to avoid
this default behavior:
```
export REMOVE_BINS="true"
```

The uninstaller supports similar configuration options as the installer. Review the
[uninstaller](https://github.com/danehans/ccptio-installer/blob/master/cleanup.sh) for details.

## Troubleshooting

Verify the Istio Client installation by using the `istioctl version` command. You should receive output similar to the
following:
```
Version: 1.0.0
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
