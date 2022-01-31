# Getting started with _pixolution Flow_ docker

This guide explains how to run _pixolution Flow_ using the dockerized images from [Docker Hub](https://hub.docker.com/r/pixolution/flow-hub).
It serves as a starting point and cheat sheet for different scenarios:
1. Standalone Docker,
1. Docker Swarm,
1. docker-compose and
1. Kubernetes

# Preparation
* Clone this repo
* Unzip the provided _pixolution Flow_ module jars (e.g. `pixolution-flow-4.0.3-solr-8.11.zip` or your custom AI modules) into the `flow-jars/` folder:
```
unzip pixolution-flow-4.0.3-solr-8.11.zip
```
* Download the dependencies of the _Flow_ modules:
```
bash download_deps.sh
```

Make sure all module jars as well as their third-party dependencies are placed in the `flow-jars/` folder.

**Please note:** All examples use [docker named volumes](https://docs.docker.com/storage/volumes/) to persist the index data in `/var/solr/`. The folder also contains the log configuration, the `solr.xml` global configuration file as well as the `pixolution-flow-4.0.3-solr-8.11.jar` plugin jar. Using docker volumes ensures the data is synced to
volume before it is over-mounted. When using bind-mounts instead, the `/var/solr` folder would be overlaid and you need to manually populate the folder with the needed files.


## Standalone docker
Install a recent version of [docker](https://docs.docker.com/engine/install/) or a drop-in alternative like [podman](https://podman.io/getting-started/).
Create a named volume for the index data
```
docker volume create flow-index
```

Start the _pixolution Flow_ image in background
```
docker run --rm -p 8983:8983 -v flow-index:/var/solr -v "$(pwd)/flow-jars:/pixolution" --name pixolution-flow -d pixolution/flow-hub:4.0.3-8.11
```

Inspect that the container is running
```
docker ps
```

Inspect _pixolution Flow_ instance logs
```
docker logs -f $(docker ps --format '{{.ID}} {{.Names}}'| grep pixolution-flow | cut -d" " -f1)
```

Initialize _pixolution Flow_ once and check if it can be loaded and configure its fields:
```
curl "http://localhost:8983/solr/my-collection/pixolution"
```

Stop the running container (shutdown)
```
docker stop $(docker ps --format '{{.ID}} {{.Names}}'| grep pixolution-flow | cut -d" " -f1)
```

Delete named volume with index data (wipe persistent data)
```
docker volume ls
docker volume rm flow-index
```


## Docker Swarm stack
Install a recent version of [docker](https://docs.docker.com/engine/install/).
Init a docker swarm
```
docker swarm init
```

Deploy stack to the swarm
```
docker stack deploy -c docker-compose.yml flow-stack
```

Initialize _pixolution Flow_ once and check if it can be loaded and configure its fields:
```
curl "http://localhost:8983/solr/my-collection/pixolution"
```

Inspect stack
```
docker stack ls
docker stack ps flow-stack
```

Inspect _pixolution Flow_ instance logs
```
docker service ls
docker service logs -f flow-stack_solr
```

Dlete stack (shutdown)
```
docker stack rm flow-stack
```

Delete named volume with index data (wipe persistent data)
```
docker volume ls
docker volume rm flow-stack_flow-index
```

## docker-compose ensemble
Install [docker](https://docs.docker.com/engine/install/) or any other container environment that supports docker-compose definitions (e.g. [podman and docker-compose](https://www.redhat.com/sysadmin/podman-docker-compose))
Install the [docker-compose scripts](https://docs.docker.com/compose/install/)
Start the ensemble
```
docker-compose -d up
```

Initialize _pixolution Flow_ once and check if it can be loaded and configure its fields:
```
curl "http://localhost:8983/solr/my-collection/pixolution"
```

Inspect ensemble
```
docker-compose images
```

Inspect _pixolution Flow_ instance logs
```
docker-compose logs -f
```

Remove ensemble (shutdown)
```
docker-compose down
```

Delete named volume with index data (wipe persistent data)
```
docker volume ls
docker volume rm flow-docker-examples_flow-index
```

## Kubernetes deployment as SolrCloud

A deployment into Kubernetes is more complex because bind-mount folders the _pixolution Flow_ jars contradicts the philosophy of Kubernetes. The easiest way is to build a new docker image that include all needed jars. This is the most flexible and robust way. To provide the customized image to your Kubernetes you need a private docker registry that Kubernetes is able to access.

Make sure that the following tools are installed:
 * [docker](https://docs.docker.com/engine/install/)
 * [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
 * [helm](https://helm.sh/docs/intro/install/)

The first step is to build a new image that include all needed jars using the provided `Dockerfile` (note the `.` at the end)
```
docker build --build-arg image="pixolution/flow-hub:4.0.3-8.11" -t registry.your-domain.com/customized-flow-docker:4.0.3-8.11 .
```

Allow docker access to your private registry:
```
docker login registry.your-domain.com
```

Push the newly built image `registry.your-domain.com/customized-flow-docker:4.0.3-8.11` to your private registry
```
docker push registry.your-domain.com/customized-flow-docker:4.0.3-8.11
```

To deploy a SolrCloud to Kubernetes we use the [solr-operator helm chart](https://apache.github.io/solr-operator/docs/running-the-operator.html).
```
helm repo add apache-solr https://solr.apache.org/charts
kubectl create -f https://solr.apache.org/operator/downloads/crds/v0.5.0/all-with-dependencies.yaml
helm install solr-operator apache-solr/solr-operator --version 0.5.0
```

Grant Kubernetes [access to your private registry](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/):
```
kubectl create secret docker-registry regcred-flow --docker-server=registry.your-domain.com --docker-username=<your-name> --docker-password=<your-pword> --docker-email=<your-email
```

Create a SolrCloud configuration, save it as `flow-cloud-definition.yaml`. Below is a minimal example, see the official documentation for the [helm chart](https://artifacthub.io/packages/helm/apache-solr/solr#chart-values) and the [solr-cloud-crd documentation](https://apache.github.io/solr-operator/docs/solr-cloud/solr-cloud-crd.html) for all available options
```
apiVersion: solr.apache.org/v1beta1
kind: SolrCloud
metadata:
  name: flow-cloud
spec:
  dataStorage:
    persistent:
      pvcTemplate:
        spec:
          resources:
            requests:
              storage: 10Gi
      reclaimPolicy: Delete
  replicas: 3
  solrImage:
    repository: registry.your-domain.com/customized-flow-docker
    tag: 4.0.3-8.11
    imagePullSecret: regcred-flow
  solrJavaMem: -Xms500M -Xmx5000M
  updateStrategy:
    method: StatefulSet
  zookeeperRef:
    provided:
      image:
        pullPolicy: IfNotPresent
        repository: pravega/zookeeper
        tag: 0.2.13
      persistence:
        reclaimPolicy: Delete
        spec:
          accessModes:
          - ReadWriteOnce
          resources:
            requests:
              storage: 10Gi
      replicas: 1
```

Deploy the SolrCloud definition to your Kubernetes cluster
```
kubectl apply -f flow-cloud-definition.yaml
```
