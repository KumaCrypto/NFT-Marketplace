/* eslint-disable prettier/prettier */
/* eslint-disable node/no-unpublished-import */
import { task } from "hardhat/config";


const contractAddress = "0xCEEF5dc5a78f4420Befa8018bD890Fb503B2cb69";

task("createItem", "Create your ERC-721 token on markeplace")
    .addParam("uri", "Token URI")
    .addParam("owner", "On what address to create a token ?")
    .setAction(async function (taskArgs, hre) {
        const marketplace = await hre.ethers.getContractAt("Marketplace", contractAddress);
        await marketplace.createItem(taskArgs.uri, taskArgs.owner);
    });