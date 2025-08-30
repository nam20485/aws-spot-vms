# **Setup Guide: Ubuntu GPU Cloud Workstation with FSx for Lustre**

This guide will walk you through deploying a high-performance, **Ubuntu-based** cloud workstation on AWS using the provided Terraform scripts.

### **Step 1: Prepare Your Project Directory**

1. Create a new, empty folder on your computer (e.g., ubuntu-workstation).  
2. Save the four files provided into this new folder:  
   * main.tf  
   * variables.tf  
   * workstation\_setup.sh  
   * instructions.md (This file)

### **Step 2: Edit the variables.tf file**

1. Open the variables.tf file in a text editor.  
2. **Crucially**, change the default value for the key\_name variable from "your-key-pair-name" to the **exact name of the EC2 key pair** you have in your AWS account for that region.  
3. Save the file.

### **Step 3: Run Terraform**

1. Open your command line terminal and navigate into the ubuntu-workstation directory.  
2. Initialize Terraform. This downloads the AWS provider.  
   terraform init

3. Apply the configuration. This will show you a plan and ask for confirmation.  
   terraform apply

4. Review the plan and type yes when prompted. The process will take about **10-15 minutes**, primarily to provision the FSx file system.

### **Step 4: Connect to Your Ubuntu Workstation**

Once terraform apply is complete, it will output a public IP address. You will connect to the machine using SSH.

1. Make sure your private key file (.pem) is secure.  
   \# On macOS or Linux  
   chmod 400 /path/to/your-key-file.pem

2. Connect using the SSH command. The default username for Ubuntu AMIs is ubuntu.  
   ssh \-i /path/to/your-key-file.pem ubuntu@\<THE\_PUBLIC\_IP\_ADDRESS\>

   Replace \<THE\_PUBLIC\_IP\_ADDRESS\> with the IP from the Terraform output.

### **Step 5: Verify the Setup**

The instance will reboot itself once after the setup script runs. If your first SSH connection fails, wait a minute and try again.

1. **Check FSx Mount:** Once connected, run the df \-h command. You should see the FSx file system mounted at /fsx.  
   df \-h  
   \# You should see a line that looks something like this:  
   \# 172.31.11.109@tcp:/e2q5eplf /fsx   lustre  1.1T  ...

2. **Check NVIDIA Drivers:** Run the nvidia-smi command. You should see a report detailing the NVIDIA driver version and the attached GPU (e.g., Tesla T4).  
   nvidia-smi

Your Ubuntu cloud workstation is now ready to use\!

### **Cleaning Up**

When you are finished, run terraform destroy from the same directory to delete all the resources and stop incurring costs.