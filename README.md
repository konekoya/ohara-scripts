# Ohara scripts

These are scripts that do what I otherwise have to do manually

## Prerequisites

- NodeJS
- Yarn

## Setup

1. Clone this repo
2. Run yarn from the root dir to install required dependencies
3. Edit your `.bashrc` or `.zshrc` so the script can be called anywhere from your terminal

```sh
# Include ohara script in your path, assuming you didn't change the repo name while cloning
export PATH="PATH_TO_YOUR_CLONED_REPO/ohara-scripts:$PATH"
```

4. Edit the `.env.sample` file in the root dir and supply all envs then change the file name from `.env.sample` -> `.env`

> Note that in order to run k8s mode, you will need a master node and a slave node. You can tweak the script to include as many slave nodes as you want

## Available scripts


### Run 🚀

Start a configurator 

```sh
runOhara
```

There are three different configurator modes that we can use when starting with the script (defaults to K8s mode):

Start a fake mode configurator, this mode is often for end-to-end testing, the returned data from the endpoint are mock data

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

Recommended for production if you have k8s support, otherwise, use docker mode instead

### Stop 💣

Remove all k8s pods and configurator container 

```sh
cleanup
```

### Utilities 🛠

Rebuild local Ohara repo's jars

```sh
updateJars
```

Update Local Ohara repo via Git

```sh
updateBranch
```

Update Remote master and slave Docker images

```sh
updateImages
```


List all envs like Docker image version, remote server IP and container name etc.

```sh
listEnv
```
