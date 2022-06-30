import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const fn: DeployFunction = async function ({ deployments: { deploy, get }, ethers: { getSigners }, network, getNamedAccounts }: HardhatRuntimeEnvironment) {
  const deployer = (await getSigners())[0];

  const {treasuryPool, distributionPool, marketingPool, expensePool, cashoutPool} = await getNamedAccounts();
  const joeRouterAddress = '0x60aE616a2155Ee3d9A68541Ba4544862310933d4';
  const nodeManagerContract = await get('NodeRewardController');

  console.log('token: ', treasuryPool, joeRouterAddress, nodeManagerContract.address)
  const contractDeployed = await deploy('EasyToken', {
    from: deployer.address,
    log: true,
    skipIfAlreadyDeployed: true,
    args: [
      [treasuryPool, distributionPool, marketingPool, expensePool, cashoutPool],
      joeRouterAddress,
      nodeManagerContract.address
    ]
  });
  console.log('npx hardhat verify --network '+ network.name +  ' ' + contractDeployed.address);
};
fn.skip = async (hre) => {
  return false;
  // Skip this on kovan.
  const chain = parseInt(await hre.getChainId());
  return chain != 1;
};
fn.tags = ['Token'];
fn.dependencies = ['NodeRewardController'];
export default fn;
