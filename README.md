# Learning AWS with Fakecloud
This project provides a series of tutorials and examples for learning Amazon Web Services (AWS) using a local fakecloud instance. The tutorials cover various AWS services, including S3, EC2, DynamoDB, and API Gateway. The project demonstrates how to host a static website on S3, launch and control EC2 instances, create and query DynamoDB tables, and deploy a Lambda function behind API Gateway.

## Features
* Host a static website on S3 using the AWS CLI
* Launch and control EC2 instances using the AWS CLI
* Create and query DynamoDB tables using the AWS CLI
* Deploy a Lambda function behind API Gateway using the AWS CLI
* Use Terraform to create S3 buckets and upload files

## Tech Stack
* AWS CLI
* Fakecloud
* Terraform
* JavaScript/TypeScript
* HTML/CSS/JS (for static website example)

## Installation
1. Install the AWS CLI on your local machine.
2. Set up a fakecloud instance and configure your AWS CLI to use it.
3. Install Terraform on your local machine.
4. Clone this repository and navigate to the desired tutorial directory.

## Usage
### S3 Static Website Hosting
1. Navigate to the `01_s3-static-website-hosting` directory.
2. Follow the instructions in the `README.md` file to create an S3 bucket and upload your website files.
3. Use the AWS CLI to configure the bucket for static website hosting.

### EC2 Launch and IAM Control
1. Navigate to the `02_ec2_launch_and_IAM_control` directory.
2. Follow the instructions in the `README.md` file to launch an EC2 instance and configure IAM policies.

### DynamoDB Load Data
1. Navigate to the `04_dynamo_db_load_data` directory.
2. Follow the instructions in the `README.md` file to create a DynamoDB table and load data into it.

### API Gateway and Lambda
1. Navigate to the `06_lambda_api_gateway` directory.
2. Follow the instructions in the `README.md` file to deploy a Lambda function behind API Gateway.

## Architecture
The project is organized into separate directories for each tutorial, with each directory containing a `README.md` file with instructions and examples. The tutorials demonstrate various AWS services and features, including S3, EC2, DynamoDB, and API Gateway.

## Contributing
To contribute to this project, please submit a pull request with your changes. Make sure to follow the existing code structure and conventions.

## License
This project is licensed under the MIT License. See the LICENSE file for details.