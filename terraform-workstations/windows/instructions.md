# **Setup Guide: Windows GPU Cloud Workstation with FSx**

This guide will walk you through the process of deploying a high-performance, Windows-based cloud workstation on AWS using the provided Terraform scripts.

This configuration will automatically create all the necessary resources, including:

* A new VPC with networking configured.  
* A secure, high-performance **FSx for Windows File Server** for your project data.  
* An AWS Managed **Active Directory**, which is required for the file server.  
* A GPU-powered **Windows Server 2022 EC2 instance**.  
* An **Elastic IP** to give your workstation a static, public IP address.

The process is fully automated. When finished, the workstation will have its NVIDIA drivers installed and the FSx file system will be automatically mapped as the F: drive.

### **Prerequisites**

Before you begin, you must have the following installed and configured:

1. **Terraform:** [Install Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli) on your local machine.  
2. **AWS CLI:** [Install and configure the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html) with credentials that have permission to create the resources listed above (Administrator access is recommended).  
3. **An AWS EC2 Key Pair:** You need an EC2 Key Pair in the AWS region where you plan to deploy the workstation. If you don't have one, [create one in the EC2 Console](https://www.google.com/search?q=https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html%23having-an-ec2-key-pair). You will need the .pem file to get your Windows password later.

### **Step 1: Prepare Your Project Directory**

1. Create a new, empty folder on your computer (e.g., windows-workstation).  
2. Save the three files I provided into this new folder:  
   * main.tf  
   * variables\_and\_outputs.tf  
   * workstation\_setup.ps1

Your folder should look like this:

windows-workstation/  
├── main.tf  
├── variables\_and\_outputs.tf  
└── workstation\_setup.ps1

### **Step 2: Run Terraform to Build Your Workstation**

1. Open your command line terminal and navigate into the windows-workstation directory you just created.  
2. Initialize Terraform. This downloads the necessary AWS provider plugin. You only need to do this once.  
   terraform init

3. Apply the configuration. This command will analyze the files and show you a plan of all the resources it will create.  
   terraform apply

4. Terraform will ask for confirmation. Review the plan and type yes and press Enter.

**Patience is key\!** This step will take **25-40 minutes** to complete. The AWS Managed Active Directory and FSx file system are complex resources and take a while for AWS to provision. Go grab a coffee.

### **Step 3: Get Your Windows Administrator Password**

Once terraform apply is finished, it will print the public IP address of your workstation. However, for security, AWS does not expose the default Administrator password. You must decrypt it using your private key file.

1. Go to the **EC2 Dashboard** in your AWS Console.  
2. Select the running "GPU-Cloud-Workstation" instance.  
3. Click the **Connect** button at the top.  
4. Go to the **RDP client** tab.  
5. Click the **Get password** button.  
6. You will be prompted to upload your private key file (the .pem file from the prerequisites). Upload it, and AWS will decrypt and display your Administrator password.  
7. Copy this password securely.

### **Step 4: Connect to Your Workstation**

1. Open your favorite Remote Desktop (RDP) client.  
   * **Windows:** Use the built-in "Remote Desktop Connection".  
   * **macOS:** Use the "Microsoft Remote Desktop" app from the App Store.  
2. For the computer name, enter the workstation\_public\_ip from the Terraform output.  
3. When prompted for credentials, use:  
   * **Username:** Administrator  
   * **Password:** The password you decrypted from the AWS Console.  
4. Connect to the instance. The first time you log in, the workstation\_setup.ps1 script will complete its final steps and the machine will automatically reboot. After the reboot, you can log in again.

### **Step 5: Verify Everything is Working**

After you log in for the second time (post-reboot), check the following:

1. **FSx Drive:** Open File Explorer. You should see a new network drive mapped as **F:**. This is your persistent, high-performance storage.  
2. **NVIDIA Drivers:** Right-click the Start Menu, go to **Device Manager**, and expand **Display adapters**. You should see the NVIDIA GPU listed there (e.g., NVIDIA T4).

Your Windows cloud workstation is now ready to use\!

### **Step 6: Cleaning Up (Important\!)**

When you are finished with the workstation, you can destroy all the resources created by Terraform to avoid incurring further costs.

1. In your terminal, from the same project directory, run:  
   terraform destroy

2. Type yes to confirm. This will delete the EC2 instance, FSx file system, Active Directory, and all associated networking resources.