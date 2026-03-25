# Adding Models to VLM Edge Studio

This guide explains how to manually download and add a new available model to the VLM Edge Studio application.

## Prerequisites

- VLM Edge Studio application (either already installed or the .deb package)
- At least 10GB of free disk space


## Case 1: VLM Edge Studio NOT installed yet
If you just have the vlm-edge-studio.deb and is currently not installed you can follow the next flow:
### Step 1. Pass the .deb package to user directory of the board, you can do as follow:
> **Note:** If you just flashed your official BSP image into your i.MX board, your user would be "root"
```bash
scp vlm-edge-studio.deb user@<your boards IP>:/user/
```s

### Step 2. Install the VLM Edge Studio application
```bash
dpkg -i vlm-edge-studio.deb
```

The install procedure will try to automatically download and install the supported models from Hugging Face hub. This would take a few minutes, depending on your connection.

## Case 2: VLM Edge Studio already installed

If for some reason you have to download and install the models manually you can do as follow:

### Step 1: Download one of the supported models from [Hugging Face NXP hub](https://huggingface.co/nxp)

You can either download it manually and pass it to the board (not recommended), or download directly to the boards folder as follows:

```bash
uvx --from /usr/share/python-wheels/fetch_models-1.0.0-py3-none-any.whl fetch_models --repo-id nxp/Qwen2.5-VL-7B-Instruct-Ara240
```

> **Note:** If you have any connection trouble make sure you have properly set a wifi or ethernet connection (make sure you have correctly set connection credentials and DNS).

## Try it out!

You can now try your installed models by launching the VLM Edge Studio application:

```bash
run_vlm_edge_studio
```

## Troubleshooting

### Issue: Model Load Failure:
The model file may be corrupted or incompletely extracted. Verify the extraction was successful by checking the model.dvm:

1. Navigate to the model location and search for the model.dvm:
```bash
cd /usr/share/llm/<your installed model>/
```
2. Calculate the checksum and compare it with the original:
```bash
md5sum mode.dvm
```

Check with the model card from [Hugging Face NXP hub](https://huggingface.co/nxp)