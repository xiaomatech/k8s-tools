#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

if [[ $# < 3 ]]; then
  >&2 echo "USAGE: $0 total available useable"
  exit 1
fi

TOTAL=${1}
AVAILABLE=${2}
USEABLE=${3}

if (( $TOTAL < $AVAILABLE )); then
  >&2 echo "ERROR: TOTAL < AVAILABLE"
  exit 1
elif (( $AVAILABLE < $USEABLE )); then
  >&2 echo "ERROR: AVAILABLE < USEABLE"
  exit 1
fi

echo "TOTAL=$TOTAL"
echo "AVAILABLE=$AVAILABLE"
echo "USEABLE=$USEABLE"

read -p "Continue? [y/N]" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  >&2 echo "abort"
  exit 1
fi

# DELETE previous policies
POLICIES=$(kubectl get psp -o jsonpath='{.items[*].metadata.name}' | tr ' ' $'\n' | grep '^aaa.scale\.' || true)
if [[ -n "$POLICIES" ]]; then
  kubectl delete psp ${POLICIES}
fi
ROLES=$(kubectl get clusterrole -o jsonpath='{.items[*].metadata.name}' | tr ' ' $'\n' | grep '^aaa.scale\.' || true)
if [[ -n "$ROLES" ]]; then
  kubectl delete clusterrole ${ROLES}
fi
BINDINGS=$(kubectl get clusterrolebinding -o jsonpath='{.items[*].metadata.name}' | tr ' ' $'\n' | grep '^aaa.scale\.' || true)
if [[ -n "$BINDINGS" ]]; then
  kubectl delete clusterrolebinding ${BINDINGS}
fi

PSP_BINDING="apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: PSP_NAME
rules:
- apiGroups:
  - extensions
  resourceNames:
  - PSP_NAME
  resources:
  - podsecuritypolicies
  verbs:
  - use
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: PSP_NAME
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: PSP_NAME
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:authenticated
"
USEABLE_PSP="apiVersion: extensions/v1beta1
kind: PodSecurityPolicy
metadata:
  name: PSP_NAME
  annotations:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: '*'
spec:
  privileged: true
  allowPrivilegeEscalation: true
  allowedCapabilities:
  - '*'
  volumes:
  - '*'
  hostNetwork: true
  hostPorts:
  - min: 0
    max: 65535
  hostIPC: true
  hostPID: true
  runAsUser:
    rule: 'RunAsAny'
  seLinux:
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
  readOnlyRootFilesystem: false
---
$PSP_BINDING
"
RESTRICTED_PSP="apiVersion: extensions/v1beta1
kind: PodSecurityPolicy
metadata:
  name: PSP_NAME
spec:
  privileged: false
  allowPrivilegeEscalation: false
  allowedCapabilities:
  volumes:
  hostNetwork: false
  hostPorts:
  hostIPC: false
  hostPID: false
  runAsUser:
    rule: 'MustRunAsNonRoot'
  seLinux:
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
  readOnlyRootFilesystem: true
"
AVAILABLE_PSP="$RESTRICTED_PSP
---
$PSP_BINDING
"

# Create policies
for i in $(seq $(( TOTAL - 1 ))); do
  if (( $i < $USEABLE )); then
    NAME="aaa.scale.c.useable.${i}"
    echo "$USEABLE_PSP" | sed "s/PSP_NAME/${NAME}/" | kubectl create -f-
  elif (( $i < $AVAILABLE )); then
    NAME="aaa.scale.b.available.${i}"
    echo "$AVAILABLE_PSP" | sed "s/PSP_NAME/${NAME}/" | kubectl create -f-
  else
    NAME="aaa.scale.a.unavailable.${i}"
    echo "$RESTRICTED_PSP" | sed "s/PSP_NAME/${NAME}/" | kubectl create -f-
  fi
done
