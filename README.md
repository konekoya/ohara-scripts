# Ohara scripts

These are scripts that do what I otherwise have to do manually

## Setup

1. Drop this into your `.bashrc` or `.zshrc` so the script can be called anywhere in your terminal

```sh
# Add ohara script to the path
export PATH="/Users/joshua/Desktop/dev/ohara-scripts:$PATH"
```

2. Edit the `.env.sample` file in the root dir and supply all envs then change the file name from `.env.sample` -> `.env`

## Usage

#### List all envs like docker image version, server IP and container name etc.

```sh
listEnv
```

#### Start a configurator

```sh
runOhara
```

There are three different configurator mode that we can use when starting with the script (defaults to K8s mode):

Start a fake mode configurator

```sh
runOhara fake
```

Start a docker mode configurator

```sh
runOhara docker
```

Start a k8s mode configurator

```sh
runOhara k8s # or simply runOhara
```

#### Remove all k8s pods and configurator container

```sh
cleanup
```

#### Rebuild local ohara repo's jars

```sh
updateJars
```

#### Update Local ohara with Git

```sh
updateBranch
```

#### Update Remote master and slave docker images

```sh
updateImages
```
