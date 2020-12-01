#!/bin/bash


NAMEPREFIX=$1
LINUX_USER=$2

set -euo pipefail

if [ -z "$NAMEPREFIX" ]; then
  usage
  exit 1
fi

if [ -z "$LINUX_USER" ]; then
  usage
  exit 1
fi

usage() {
  echo "post-provision.sh NAMEPREFIX LINUX_USER"
}


_log() {
  echo "----> $@"
}

_fail() {
  echo "FAILED: $@"
  exit 1
}

_tunnelssh() {
  local instance=$1; shift

  gcloud compute ssh --ssh-flag=-A $(_jumpbox) -- ssh -o "StrictHostKeyChecking=no" $instance -- $@
}


PRODUCTION_REGISTRY="${NAMEPREFIX}-airgap-production-registry"
STAGING_REGISTRY="${NAMEPREFIX}-staging-registry"

_instances() {
  echo $(_productioninstances) $(_staginginstances)
}

_jumpbox() {
  echo "${NAMEPREFIX}-jump-box"
}

_registryinstances() {
  echo "${PRODUCTION_REGISTRY}" "${STAGING_REGISTRY}"
}

_productioninstances() {
  echo "${NAMEPREFIX}-airgap-production-registry" \
    "${NAMEPREFIX}-airgap-production-cluster"
}

_staginginstances() {
  echo "${NAMEPREFIX}-staging-registry" \
    "${NAMEPREFIX}-staging-cluster"
}


insecureRegistries() {
  for instance in $(_staginginstances); do
    _log "configuring docker insecure registries on ${instance} --> ${STAGING_REGISTRY}"
    gcloud compute ssh $instance -- "sudo mkdir -p /etc/docker && echo \"{\\\"insecure-registries\\\":[\\\"${STAGING_REGISTRY}:32000\\\"]}\" | sudo tee /etc/docker/daemon.json"
  done

  for instance in $(_productioninstances); do
    _log "configuring docker insecure registries on ${instance} --> ${PRODUCTION_REGISTRY}"
    gcloud compute ssh $instance -- "sudo mkdir -p /etc/docker && echo \"{\\\"insecure-registries\\\":[\\\"${PRODUCTION_REGISTRY}:32000\\\"]}\" | sudo tee /etc/docker/daemon.json"
  done
}


# Install a minimal kubernetes cluster on all nodes: https://kurl.sh/9142763
installk8s() {
  for instance in $(_instances); do
    _log "installing kubernetes via kurl install on ${instance}"
    gcloud compute ssh $instance -- "curl -sfL https://k8s.kurl.sh/9142763 | sudo bash | sed -e 's/^/[${instance}]: /;'" &
  done
  wait

  for instance in $(_instances); do
    gcloud compute ssh $instance -- "sudo usermod -aG docker $LINUX_USER"
  done
}


# deploy a minimal registry to the registry instances
# node port 32000 with username/password of kots:kots
deployRegistry() {
  for instance in $(_registryinstances); do
    _log "deploying default kots:kots docker registry on ${instance} w/ node port 32000"
    gcloud compute ssh $instance -- kubectl --kubeconfig /home/$LINUX_USER/admin.conf apply -f https://raw.githubusercontent.com/replicatedhq/replicated-automation/master/customer/existing-cluster-airgap/plain-registry.yaml
    until gcloud compute ssh $instance -- kubectl --kubeconfig /home/$LINUX_USER/admin.conf wait --for=condition=ready pod/registry-0 -n registry; do sleep 5; done
    _log "testing registry on ${instance}"
    gcloud compute ssh $instance -- docker pull alpine:latest
    gcloud compute ssh $instance -- docker tag alpine:latest ${instance}:32000/alpine:latest
    gcloud compute ssh $instance -- docker login --username kots --password kots ${instance}:32000;
    gcloud compute ssh $instance -- docker push ${instance}:32000/alpine:latest
  done

}

# remove the IP from production instances
removeaddresses() {
  for instance in $(_productioninstances); do
    _log "Removing external IP from ${instance}"
    gcloud compute instances delete-access-config "${instance}" --access-config-name="External NAT" || gcloud compute instances delete-access-config "${instance}" --access-config-name=external-nat
  done
}

# ssh each instance via the jump box and verify it has no outbound internet
# test by using curl with a 5s timeout
testairgap() {
  _log "Checking that production instances have no outbound internet (synthetic airgap)"
  set +e
  for instance in $(_productioninstances); do
    _log -n "Verifying that ${instance} cannot reach https://kubernetes.io... "
    gcloud compute ssh --ssh-flag=-A $(_jumpbox) -- ssh -o "StrictHostKeyChecking=no" $instance --  curl -fsSL -m 5 https://kubernetes.io
    if [ "$?" != "28" ]; then
      _fail "airgap check failed, ${instance} was able to reach kubenetes.io"
    fi
  done
  set -e
}

reloadDocker() {
  for instance in $(_instances); do
    gcloud compute ssh $instance -- sudo systemctl restart docker
  done
}

howManyPortForwardsWeGotOnThisShip() {
  # forward production registry from workstation
  # forward production kots instance from workstation
  echo "apparently none"

}


waitForReady() {
  for instance in $(_instances); do
    until gcloud compute ssh $instance -- exit; do sleep 5; done
  done
}

getKubeconfigs() {
  for instance in $(_instances); do
    gcloud compute ssh --ssh-flag=-A $(_jumpbox) -- scp $instance:admin.conf ./$instance-kubeconfig.conf
  done
}


main() {

  waitForReady
  insecureRegistries
  installk8s

  # reloadDocker

  deployRegistry
  removeaddresses
  testairgap
  getKubeconfigs



  # howManyPortForwardsWeGotOnThisShip
}
main
