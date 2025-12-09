## Secure Video Streaming using CloudFront Signed URLs

Infrastructure-as-code to implement the solution in this [blog post](https://aws.amazon.com/blogs/networking-and-content-delivery/secure-and-cost-effective-video-streaming-using-cloudfront-signed-urls/).

Some manual steps are required before you can deploy the solution. More info [here](https://hlsbook.net/secure-video-streaming-using-cloudfront-signed-urls/).

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