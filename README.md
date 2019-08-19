# K8s Core Cluster (POC)

Uses Terraform 0.12.x

Post the initial setup you need to activate the configmaps

```bash
aws --region "eu-west-1" --profile "dev" eks update-kubeconfig --name "eks-core-cluster"
terraform12 output config_map_aws_auth > configmap.yml
AWS_PROFILE="dev" kubectl apply -f configmap.yml
```

You should be able to then see the worker nodes in the `kubectl get nodes` command.

```bash
AWS_PROFILE="dev" kubectl get nodes
NAME                                          STATUS   ROLES    AGE     VERSION
ip-10-44-152-227.eu-west-1.compute.internal   Ready    <none>   24s     v1.13.7-eks-c57ff8
ip-10-44-153-45.eu-west-1.compute.internal    Ready    <none>   7m36s   v1.13.7-eks-c57ff8
ip-10-44-154-117.eu-west-1.compute.internal   Ready    <none>   21s     v1.13.7-eks-c57ff8
```