# GitOps with ArgoCD

Making Git the source of truth. Deploy and manage the Cloud Native Notes application using ArgoCD, the declarative GitOps operator for Kubernetes
 
## Week 8 - Tasks
- Create namespace `argocd`
- Install ArgoCD on your kind cluster.
  - You can use Helm Chart or the official manifests `install.yaml` for ArgoCD
- Obtain the initial admin password to login
- Push your manifests `week8` to a Git repository.
- Create an ArgoCD Application and the ArgoCD Ingress
  - The manifest files are in the `week8/k8s/argocd` directory.
  - Update the repoURL in the `application.yaml` to point to your repo 
- Check the ArgoCD UI via the Ingress controller at https://argocd.127-0-0-1.nip.io.
  - NOTE: This requires SSL passthrough on the ingress controller.
- Sync the application and verify all resources are created.
- Confirm Sync Status = Synced and Health Status = Healthy.
- Test GitOps: change something in a manifest, commit, push, and watch ArgoCD auto-sync.
- Test self-healing: manually delete or scale a resource out of band and watch ArgoCD revert it.

## Extra Challenges
1. ArgoCD Image Updater.
    Can you make ArgoCD automatically deploy a new image tag when it's pushed to a registry?
    Read up on argocd-image-updater and see if you can wire it up to cloud-native-notes:4.0.

2. Sealed Secrets.
    Your redis-secret currently sits in Git as plaintext (stringData). That's not acceptable for real GitOps.
    Convert the secret to a SealedSecret using Bitnami's kubeseal.
    Commit only the encrypted form to Git.

## To Think About

- Why is Git the single source of truth in GitOps?
- What's the difference between push-based CI/CD (like GitHub Actions applying kubectl) and pull-based GitOps (like ArgoCD)?

## Solution Guide

- SSL Passthrough on ingress-nginx
  ```
  kubectl patch deployment ingress-nginx-controller -n ingress-nginx \
    --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--enable-ssl-passthrough"}]'
  ```



## Verify

Run the verification script `./verify-week8.sh`

If your verification score is 100%, you are a star!

If not, read the report and rectify the error(s).

If you are stucked after several trials, ask for help in the group.

If you have got this far, you are a champion! Celebrate yourself and I hope you enjoyed the bootcamp. Keep building. The world is watching.
--