# Observability

Add Prometheus metrics and structured logging. Then view metrics on Grafana
 
## Week 7 - Tasks
- Build and load `cloud-native-notes:4.0`
- Rollout the updated backend deployment
- Add a ServiceMonitor and Monitoring ingress for the backend. 
    - The manifest files can be found in `k8s/observability` directory
- Install Helm chart for Prometheus
- Obtain the admin password to login to Grafana. 
    - You would see how to retrive it after installing your Helm chart
    - Do not port forward to access Grafana and Promethues. 
    - Ingress will route the traffic to both services.
- Login to Grafana at `http://status.notes.127-0-0-1.nip.io` to explore available dashboards.  
- Visit the Prometheus page at `http://metrics.notes.127-0-0-1.nip.io` and query some metrics

## Extra Challenges
1. Use promql to query Prometheus for the app metrics on the following 
    - `http_requests_total`
    - `http_requests_created`
    - `notes_created_total`
    - `active_notes`
   
2. Build a new Grafana dashboard based on those app metrics to observe your app
3. Post more notes on the Cloud Native Notes app at `http://notes.127-0-0-1.nip.io` and observe on the dashboard 

## To Think About

- Why is observability important?
- What is Helm used for? Why are we using it?

## Solution Guide

- Install Prometheus and create the monitoring namespace
    ```
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

    helm repo update
    
    helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
    ```

- Building Your Own Dashboards

    NOTE: You can explore the various dashboards that tells you more about your nodes, pods and other Kubernetes objects. Additionally, you can build your own too.

    **Workflow:**  FastAPI  → /metrics → Service → ServiceMonitor → Prometheus → PromQL

    1. *On Prometheus go to:*
        
          Status → Target health

        **Expected Result:**

        You should now see a target corresponding to your backend, with something like: `serviceMonitor/cloud-native-notes/backend-monitor/0`  
        You can now query your application once the target is UP. See the extra challenge section for some queries.



   2. *On Grafana go to:* 
   
        Dashboards → New → New dashboard 

        Click on the + to add a new panel. Then click on Configure Visualization
    
        **I. Active Notes Dashboard**

        On the page, switch from Builder to Code. You should then get a text box where you can enter PromQL.
        

        Query: `active_notes`

        Then click Run queries. You should see a graph appear in the large area above.

        Set the visualization.

        On the right-hand side, click: `All visualizations`

        Then select: `Stat`
        
        Title: `Active Notes`
        

        Grafana will ask you to save the dashboard first. You can call the dashboard:
        `Cloud Native Notes - Application Observability`
        Then save it.

        You can explore and create other interesting dashboard for your application metrics or view the infrastructure metrics.


## Verify

Run the verification script `./verify-week7.sh`

If your verification score is 100%, you are good to go!

If not, read the report and rectify the error(s).

If you are stucked after several trials, ask for help in the group.