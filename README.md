## Secure Video Streaming using CloudFront Signed URLs

Infrastructure-as-code to implement the solution in this [blog post](https://aws.amazon.com/blogs/networking-and-content-delivery/secure-and-cost-effective-video-streaming-using-cloudfront-signed-urls/).

You'll need to create a keypair before you can deploy the solution. For context, the signer uses the private key to sign the URL and CloudFront uses the public key to validate the signature. From the terminal, run the following commands:
```
$ openssl genrsa -out private_key.pem 2048
$ openssl rsa -pubout -in private_key.pem -out public_key.pem
```
By default, Terraform will look in the current directory for the keys. If you've saved them somewhere else, you'll need to set the corresponding variables when running Terraform.

Run the following commands to deploy the solution to your AWS account:
```
$ terraform init
$ terraform plan \
   -var="bucket_name=<bucket name>" \
   -out=tfplan
$ terraform apply tfplan
```
More info [here](https://hlsbook.net/secure-video-streaming-using-cloudfront-signed-urls/).