# Getting started with pixolution Flow docker

The following guide explains how to run pixolution Flow using the dockerized images from [docker hub](https://hub.docker.com/r/pixolution/flow-hub)

# Preparation
* Clone this repo
* Unzip your pixolution Flow module jars (either the `pixolution-flow-4.0.3-solr-8.11.zip` or your custom AI modules) into a folder `flow-jars/` beside the `docker-compose.yml` file. In case of a pixolution Flow release ZIP run the following commands:
```
unzip pixolution-flow-4.0.3-solr-8.11.zip
bash download_deps.sh
```

Make sure all module jars as well as their third-party dependencies are placed in the `flow-jars/`

**Please note:** All examples use [docker named volumes](https://docs.docker.com/storage/volumes/) to persist the index data in `/var/solr/`. The folder also contains the log configuration, the `solr.xml` global configuration file as well as the `pixolution-flow-4.0.3-solr-8.11.jar` plugin jar. Using docker volumes makes sure this data is synced to
the volume before it is over-mounted. When using bind-mounts the `/var/solr` folder would be overlaid and you need to manually populate the folder with the needed files.


## Standalone docker
* install a recent version of [docker](https://docs.docker.com/engine/install/) or a drop-in alternative like [podman](https://podman.io/getting-started/)
* create a named volume for the index data
```
docker volume create flow-index
```

* start the pixolution Flow image in background
```
docker run --rm -p 8983:8983 -v flow-index:/var/solr -v "$(pwd)/flow-jars:/pixolution" --name pixolution-flow -d pixolution/flow-hub:4.0.3-8.11
```

* inspect that the container is running
```
docker ps
```

* inspect pixolution flow instance logs
```
docker logs -f $(docker ps --format '{{.ID}} {{.Names}}'| grep pixolution-flow | cut -d" " -f1)
```

* check whether pixolution Flow could be loaded and to automatically create the needed fields, call once:
```
curl "http://localhost:8983/solr/my-collection/pixolution"
```

* stop the running container (shutdown)
```
docker stop $(docker ps --format '{{.ID}} {{.Names}}'| grep pixolution-flow | cut -d" " -f1)
```

* delete named volume with index data (wipe persistent data)
```
docker volume ls
docker volume rm flow-index
```


## Docker Swarm stack
* install a recent version of [docker](https://docs.docker.com/engine/install/)

* init a docker swarm
```
docker swarm init
```

* deploy stack to the swarm
```
docker stack deploy -c docker-compose.yml flow-stack
```

* check whether pixolution Flow could be loaded and to automatically create the needed fields, call once:
```
curl "http://localhost:8983/solr/my-collection/pixolution"
```

* inspect stack
```
docker stack ls
docker stack ps flow-stack
```

* inspect pixolution flow instance logs
```
docker service ls
docker service logs -f flow-stack_solr
```

* delete stack (shutdown)
```
docker stack rm flow-stack
```

* delete named volume with index data (wipe persistent data)
```
docker volume ls
docker volume rm flow-stack_flow-index
```

## docker-compose ensemble
* install [docker](https://docs.docker.com/engine/install/) or any other container environment that supports docker-compose definitions (e.g. [podman and docker-compose](https://www.redhat.com/sysadmin/podman-docker-compose))
* install the [docker-compose scripts](https://docs.docker.com/compose/install/)

* start the ensemble
```
docker-compose -d up
```

* check whether pixolution Flow could be loaded and to automatically create the needed fields, call once:
```
curl "http://localhost:8983/solr/my-collection/pixolution"
```

* inspect ensemble
```
docker-compose images
```

* inspect pixolution flow instance logs
```
docker-compose logs -f
```

* remove ensemble (shutdown)
```
docker-compose down
```

* delete named volume with index data (wipe persistent data)
```
docker volume ls
docker volume rm flow-docker-examples_flow-index
```

## Kubernetes deployment as SolrCloud

A deployment into Kubernetes is more complex since bind-mount folders to provide the pixolution Flow module jars contradicts the philosophy of Kubernetes. The easiest way is to build a new docker image that include all needed jars. This is the most flexible and robust way. To provide the customized image to your Kubernetes there is also a private docker registry needed that Kubernetes is able to access.

Make sure that the following tools are installed:
 * [docker](https://docs.docker.com/engine/install/)
 * [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
 * [helm](https://helm.sh/docs/intro/install/)

First step is to build a new image that include all needed jars using the provided `Dockerfile` (note the `.` at the end)
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

* Deploy the SolrCloud definition to your Kubernetes cluster
```
kubectl apply -f flow-cloud-definition.yaml
```
