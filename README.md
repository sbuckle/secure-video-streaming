## Secure Video Streaming using CloudFront Signed URLs

Infrastructure-as-code to implement the solution in this [blog post](https://aws.amazon.com/blogs/networking-and-content-delivery/secure-and-cost-effective-video-streaming-using-cloudfront-signed-urls/).

Some manual steps are required before you can deploy the solution. More info [here](https://hlsbook.net/secure-video-streaming-using-cloudfront-signed-urls/).

The first thing you need to do is create a keypair. For context, the signer uses the private key to sign the URL and CloudFront uses the public key to validate the signature. From the terminal, run the following commands:
```
$ openssl genrsa -out private_key.pem 2048
$ openssl rsa -pubout -in private_key.pem -out public_key.pem
```
Navigate to the CloudFront console. From the menu on the left-hand side, under **Key Management**, select **Public keys**. Click on *Create public key*. Paste the contents of the file `public_key.pem` into the appropriate field. Make a note of the ID. The Terraform creates a trusted key group for you so you can skip that step.

Next, you’ll need to create a secret that stores the private key. Navigate to the Secrets Manager console to create a new secret. For secret type, choose **Other type of secret**. Under the **Key/value pairs** header, select **Plaintext** then paste the contents of the `private_key.pem`. Following the remaining steps. Make sure automatic rotation is disabled. Make a note of the secret’s name as you’ll need to supply it as a variable when you run the Terraform.

Run the following commands to deploy the solution to your AWS account:
```
$ terraform init
$ terraform plan \
   -var="bucket_name=<bucket name>" \
   -var "sm_secret_name=<secret name> \
   -var="cf_key_id=<key id>" \
   -out=tfplan
$ terraform apply tfplan
```