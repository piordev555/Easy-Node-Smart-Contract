import { DeployFunction } from 'hardhat-deploy/types';

const fn: DeployFunction = async function ({ deployments: { deploy }, ethers: { getSigners }, network }) {
  const deployer = (await getSigners())[0];

  const _nodePrice = 10 * 10 ** 18; // 10 $EASY
  const _rewardPerNode = 9 * 10 ** 17; // 0.9 $EASY per Node
  const _claimInterval = 10; // 1d, unit is second

  console.log('nodeRewardManager: ', _nodePrice, _rewardPerNode, _claimInterval, deployer.address);
  const contractDeployed = await deploy('NodeRewardController', {
    from: deployer.address,
    log: true,
    skipIfAlreadyDeployed: true,
    args: [
      _nodePrice.toString(),
      _rewardPerNode.toString(),
      _claimInterval.toString()
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
fn.tags = ['NodeRewardController'];

export default fn;
