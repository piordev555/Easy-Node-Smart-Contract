import { DeployFunction } from 'hardhat-deploy/types';

const fn: DeployFunction = async function ({ deployments: { deploy, get, execute, read }, ethers: { getSigners }, network }) {
  const deployer = (await getSigners())[0];
  const tokenContract = await get('EasyToken');

  await execute(
    'NodeRewardController',
    {from: deployer.address, log: true},
    'setToken',
    tokenContract.address
  );

  console.log('set_parameter_for_nodecontroller:');
};
fn.skip = async (hre) => {
  return false;
  // Skip this on kovan.
  const chain = parseInt(await hre.getChainId());
  return chain != 1;
};
fn.tags = ['set_nodemanager_parameter'];
fn.dependencies = ['Token', 'NodeRewardController'];

export default fn;
