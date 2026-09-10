# PhotonVision image builder

GitHub Actions builds board images on pushes to `main`, version tags, and pull
requests. Images from pushes are published using the existing release workflow.

## Radxa Dragon Q6A

The `radxa-dragon-q6a` matrix entry produces
`photonvision_radxa-dragon-q6a.img.xz`. It uses Armbian Trixie current minimal
26.8.1 (kernel 6.18.2), the standard ARM64 PhotonVision installer, and the common
`photon` / `vision` login. PhotonVision controls Ethernet through NetworkManager;
wireless networking and Bluetooth are disabled. SSH is enabled.

The versioned base URL is the image resolved from
[Armbian's Trixie current minimal link](https://dl.armbian.com/radxa-dragon-q6a/Trixie_current_minimal).
Use a versioned `.img.xz` URL when updating it: photon-image-runner v2.0.0 detects
compression by filename and cannot consume the extensionless redirect directly.
The verified GPT layout is EFI partition 1 and ext4 rootfs partition 2. Shrinking
is disabled, following the other non-Raspberry Pi images.

### Boot media

Flash the **whole image**, including its EFI partition, to the target medium.
The installer preserves Armbian's kernel, Q6A device tree, bootloader, firmware,
UUID/PARTUUID references, and first-boot filesystem expansion. It does not encode
an SD, eMMC, UFS, or NVMe Linux device name, change SPI firmware, or transplant the
Rubik Pi's flash layout.

microSD, eMMC, and NVMe boot depend on the Q6A's factory SPI/UEFI firmware and its
selected boot device. UFS is not a guaranteed interchangeable flash target:
[Radxa's boot documentation](https://docs.radxa.com/en/dragon/q6a/hardware-use/boot)
describes a hardware change for direct UFS boot which disables the other boot
paths. Follow Radxa's instructions for the installed firmware and storage. This
builder does not perform that conversion or provide an EDL/rawprogram image.
Avoid connecting multiple copies of the image at once: clones share filesystem
and partition identifiers. Each boot medium still needs testing on hardware.

### NPU runtime and PhotonVision prerequisite

The installer includes Radxa FastRPC 1.0.7-2, its validation tool, and the Hexagon
v68 QNN SDK package 0.1.0-2 (QAIRT 2.42.0.251225), including
`libQnnTFLiteDelegate.so`, HTP host libraries and the v68 DSP skeleton. Package
URLs and SHA-256 hashes are pinned in `files/radxa-dragon-q6a/packages.sha256`.
Only the DSP userspace payload and license are extracted from Radxa firmware
0.2.41, retaining Armbian's kernel firmware. FastRPC initializes the Q6A DSP path
at boot; the PhotonVision service receives that search path and uses CPUs 4-7,
as on the Rubik Pi 3. Radxa's thermal control remains intact.

This prepares the runtime; **end-to-end PhotonVision NPU support is not yet
verified**. The inspected upstream
[PhotonVision platform detector](https://github.com/PhotonVision/photonvision/blob/main/photon-targeting/src/main/java/org/photonvision/common/hardware/Platform.java)
only recognizes the Rubik model name as QCS6490. A PhotonVision release must also
recognize the Q6A before it automatically exposes the existing `RUBIK` TFLite
backend. In that separate repository, extend `isQCS6490()` with the compatible
string check already used for RK3588:

```java
return currentPlatform == LINUX_QCS6490
        || Platform.isRubik()
        || fileHasText("/proc/device-tree/compatible", "qcom,qcs6490");
```

Use a release containing that change and validate its bundled TFLite delegate
against the installed QAIRT version. The builder does not alter board identity
or patch downloaded PhotonVision JARs. It also does not install Rubik's Ubuntu
packages, USB-path workaround, fan service, or SNPE tooling on Debian.

On a Q6A, verify the runtime using
[Radxa's NPU setup instructions](https://docs.radxa.com/en/dragon/q6a/app-dev/npu-dev/fastrpc-setup):

```sh
ls -l /dev/fastrpc-*
systemctl status fastrpc.service cdsprpcd.service
fastrpc_test -a v68
journalctl -b -u photonvision.service
```

Then run a quantized `RUBIK` TFLite model in PhotonVision and confirm HTP inference
actually succeeds. Also check USB camera persistence, Ethernet configuration,
temperature under sustained load, and filesystem expansion on each boot medium.
An Actions image build cannot validate these hardware behaviors.
