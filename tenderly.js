const axios = require('axios');
const dotenv = require('dotenv');
const ethers = require('ethers');

dotenv.config();

// assuming environment variables TENDERLY_USER, TENDERLY_PROJECT and TENDERLY_ACCESS_KEY are set
// https://docs.tenderly.co/other/platform-access/how-to-find-the-project-slug-username-and-organization-name
// https://docs.tenderly.co/other/platform-access/how-to-generate-api-access-tokens
const { TENDERLY_USER, TENDERLY_PROJECT, TENDERLY_ACCESS_KEY } = process.env;

const daiOnFork = async () => {
  console.time('Fork Creation');
  const fork = await mainnetFork();
  console.timeEnd('Fork Creation');

  const forkId = fork.data.simulation_fork.id;
  const rpcUrl = `https://rpc.tenderly.co/fork/${forkId}`;
  // const rpcUrl = 'https://rpc.tenderly.co/fork/###-###-###-###';
  console.log('Fork URL\n\t' + rpcUrl);

  const forkProvider = new ethers.providers.JsonRpcProvider(rpcUrl);

  const [minterAddress, ownerAddress, spenderAddress, receiverAddress] =
    await forkProvider.listAccounts();

  const [minterSigner, ownerSigner, spenderSigner] = [
    forkProvider.getSigner(minterAddress),
    forkProvider.getSigner(ownerAddress),
    forkProvider.getSigner(spenderAddress),
    forkProvider.getSigner(receiverAddress),
  ];

  /*
  // alternatively, you could as well use an existing account you do have private key access to.

  const minterAddress = '0xdc6bdc37b2714ee601734cf55a05625c9e512461';
  const minterSigner = new ethers.Wallet(
    '0x94...5c'
  ).connect(forkProvider);



  */

  await forkProvider.send('tenderly_setBalance', [
    [minterAddress],
    ethers.utils.hexValue(ethers.utils.parseUnits('10', 'ether').toHexString()),
  ]);



  // // override: make 0xdc6bdc37b2714ee601734cf55a05625c9e512461 a ward of DAI
  // await forkProvider.send('tenderly_setStorageAt', [
  //   // the DAI contract address
  //   '0x6b175474e89094c44da98b954eedeac495271d0f',
  //   // storage location wards['0xdc6bdc37b2714ee601734cf55a05625c9e512461']
  //   ethers.utils.keccak256(
  //     ethers.utils.concat([
  //       ethers.utils.hexZeroPad(minterAddress, 32), // the ward address (address 0x000..0) - mapping key
  //       ethers.utils.hexZeroPad('0x0', 32), // the wards slot is 0th  in the DAI contract - the mapping variable
  //     ])
  //   ),
  //   // flag 1 (at 32 bytes length)
  //   '0x0000000000000000000000000000000000000000000000000000000000000001',
  // ]);

  // // TX1: mint
  // await minterSigner.sendTransaction({
  //   from: minterAddress,
  //   to: '0x6b175474e89094c44da98b954eedeac495271d0f',
  //   data: DaiAbi.encodeFunctionData('mint', [
  //     ethers.utils.hexZeroPad(ownerAddress.toLowerCase(), 20),
  //     ethers.utils.parseEther('1.0'),
  //   ]),
  //   gasLimit: 800000,
  // });

  // // TX2: approve
  // await ownerSigner.sendTransaction({
  //   to: '0x6b175474e89094c44da98b954eedeac495271d0f',
  //   data: DaiAbi.encodeFunctionData('approve', [
  //     ethers.utils.hexZeroPad(spenderAddress.toLowerCase(), 20),
  //     ethers.utils.parseEther('1.0'),
  //   ]),
  //   gasLimit: 800000,
  // });

  // // TX3: transferFrom
  // await spenderSigner.sendTransaction({
  //   to: '0x6b175474e89094c44da98b954eedeac495271d0f',
  //   data: DaiAbi.encodeFunctionData('transferFrom', [
  //     ethers.utils.hexZeroPad(ownerAddress.toLowerCase(), 20),
  //     ethers.utils.hexZeroPad(receiverAddress.toLowerCase(), 20),
  //     ethers.utils.parseEther('1.0'),
  //   ]),
  //   gasLimit: 800000,
  // });

  // deleteFork(forkId);
};

// const DaiAbi = new ethers.utils.Interface([
//   {
//     constant: false,
//     inputs: [
//       { internalType: 'address', name: 'usr', type: 'address' },
//       { internalType: 'uint256', name: 'wad', type: 'uint256' },
//     ],
//     name: 'mint',
//     outputs: [],
//     payable: false,
//     stateMutability: 'nonpayable',
//     type: 'function',
//   },
//   {
//     constant: false,
//     inputs: [
//       { internalType: 'address', name: 'usr', type: 'address' },
//       { internalType: 'uint256', name: 'wad', type: 'uint256' },
//     ],
//     name: 'approve',
//     outputs: [{ internalType: 'bool', name: '', type: 'bool' }],
//     payable: false,
//     stateMutability: 'nonpayable',
//     type: 'function',
//   },
//   {
//     constant: false,
//     inputs: [
//       { internalType: 'address', name: 'src', type: 'address' },
//       { internalType: 'address', name: 'dst', type: 'address' },
//       { internalType: 'uint256', name: 'wad', type: 'uint256' },
//     ],
//     name: 'transferFrom',
//     outputs: [{ internalType: 'bool', name: '', type: 'bool' }],
//     payable: false,
//     stateMutability: 'nonpayable',
//     type: 'function',
//   },
// ]);

daiOnFork();

function deleteFork(forkId) {
  axios.delete(
    `https://api.tenderly.co/api/v1/account/${TENDERLY_USER}/project/${TENDERLY_PROJECT}/fork/${forkId}`,
    {
      headers: {
        'X-Access-Key': TENDERLY_ACCESS_KEY,
      },
    }
  );
}

async function mainnetFork() {
  return await axios.post(
    `https://api.tenderly.co/api/v1/account/${TENDERLY_USER}/project/${TENDERLY_PROJECT}/fork`,
    {
      network_id: '1',
      chain_config: {
        chain_id: 11,
        shanghai_time: 1677557088,
      },
    },
    {
      headers: {
        'X-Access-Key': TENDERLY_ACCESS_KEY,
      },
    }
  );
}

