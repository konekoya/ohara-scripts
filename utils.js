const cp = require("child_process");
const chalk = require("chalk");
const axios = require("axios");
const { getOr } = require("lodash/fp");

const config = require("./config");
require("dotenv").config({ path: config.envPath });

const userName = process.env.USER_NAME;
const masterIp = process.env.K8S_MASTER;
const slaveIp = process.env.K8S_SLAVE;
const API_ROOT = process.env.API_ROOT;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const run = (options = {}) => (command) => {
  const { isMaster = true, shouldPrint = true } = options;
  const serverIp = isMaster ? masterIp : slaveIp;
  const stdio = shouldPrint ? { stdio: "inherit" } : {};

  cp.execSync(`ssh ${userName}@${serverIp} ${command}`, stdio);
};

const getMode = async () => {
  try {
    const response = await axios.get(`${API_ROOT}/inspect/configurator`);
    return getOr(null, "data.mode", response);
  } catch (error) {
    console.log(
      chalk.red(`Oops, we cannot fetch Configurator info from ${API_ROOT}`)
    );
    console.log(error.message);
  }
};

module.exports = {
  sleep,
  run,
  getMode,
};
