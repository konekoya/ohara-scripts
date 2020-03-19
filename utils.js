const cp = require("child_process");
const config = require("./config");
require("dotenv").config({ path: config.envPath });

const userName = process.env.USER_NAME;
const masterIp = process.env.K8S_MASTER;
const slaveIp = process.env.K8S_SLAVE;

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

const run = (options = {}) => command => {
  const { isMaster = true, shouldPrint = true } = options;
  const serverIp = isMaster ? masterIp : slaveIp;
  const stdio = shouldPrint ? { stdio: "inherit" } : {};

  cp.execSync(`ssh ${userName}@${serverIp} ${command}`, stdio);
};

module.exports = {
  sleep,
  run
};
