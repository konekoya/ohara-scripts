const config = require("./config");
require("dotenv").config({ path: config.envPath });

const API_ROOT = process.env.API_ROOT;

module.exports.MODES = {
  FAKE: "FAKE",
  K8S: "K8S",
  DOCKER: "DOCKER",
};

module.exports.API_URLS = {
  CONNECTOR: `${API_ROOT}/connectors`,
  STREAM: `${API_ROOT}/streams`,
  SHABONDI: `${API_ROOT}/shabondis`,
  TOPIC: `${API_ROOT}/topics`,
  WORKER: `${API_ROOT}/workers`,
  BROKER: `${API_ROOT}/brokers`,
  ZOOKEEPER: `${API_ROOT}/zookeepers`,
  PIPELINE: `${API_ROOT}/pipelines`,
  NODE: `${API_ROOT}/nodes`,
  OBJECT: `${API_ROOT}/objects`,
};
