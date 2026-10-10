# Configuration, Secrets and Storage

Working with ConfigMaps, Secrets and PersistentVolume. 
 
**NOTE:** 

**The Cloud Native Notes backend app code has been updated. You may wish to clean up deployment from last week if you are afraid of troubleshooting.** 

**However, it is recommended that you leave the setup and figure out how you will fix things and make them work again if they break. Starting this week, we will keep building on this infrastructure along with the app and gradually keep improving it till the end of the bootcamp.**


## Week 4 - Tasks
- Build and load `cloud-native-notes:3.0` to the cluster
    -  You can use the `build-and-load.sh` script to automate it
- Create the Kubernetes objects using the manifest files in `k8s/` such as the: namespace, configmap, secret, redis deployment and backend deployment.
- Check the details of the Kubernetes objects created. -*See solution guide*
- Confirm that backend authenticates with redis. The app gracfully handles the connection.
- Port-Forward the backend service to port 3000
- Try to POST several content to the backend from another terminal
    - Post the 4 messages from last week's tasks and the 2 for this week 
    - You can also edit the title and/or content string with your customized message and post
- View your Cloud Native Notes API to see the contents and timestamps of each note posted
- Restart your backend deployment and view your notes again
    - If you can find your previous notes, then your storage and secret worked with the backend application. 

## Extra Challenges
- Currently the app can only store 100 notes. Can you increase it to 10000?
- Two secrets were configured. Which of them is been used in the cluster?
- The secret used was in plaintext. This is a security concern. 
    - Is there a better way to handle the secret? 
    - Can you implement it?
- What error did you encountered? How did you solve it?

## To Think About
- How was the backend and redis deployments able to communicate with each other?
- How was storage provisioned?
- What is the usefulness of the liveness and readiness probe in the redis deployment?


## Solution Guide

1. Check Kubernetes Objects details
    - Redis
    
        `kubectl exec -n cloud-native-notes deploy/backend -- env | grep -E '^REDIS_'`

    - Config maps

        `kubectl get configmap app-config -n cloud-native-notes -o yaml`
    - Secret

        `kubectl get secrets -n cloud-native-notes -o yaml`


2. Backend Authenticates with Redis

    *Workflow:* **Backend pod → Redis Service → Redis server → PONG**

    - *Test 1: PING Redis*

    ```
    kubectl exec deploy/backend -n cloud-native-notes -- python -c '
    import os
    import redis

    print("HOST:", os.getenv("REDIS_HOST"))
    print("PORT:", os.getenv("REDIS_PORT"))
    print("PASSWORD SET:", bool(os.getenv("REDIS_PASSWORD")))

    r = redis.Redis(
        host=os.getenv("REDIS_HOST"),
        port=int(os.getenv("REDIS_PORT")),
        password=os.getenv("REDIS_PASSWORD"),
        decode_responses=True
    )

    print("PING:", r.ping())
    '
    ```

    Expected Result: 

    **PASSWORD SET: True**

    **PING: True**

    - Test 2: *Check Read-Write Connection*

    ```
    kubectl exec -n cloud-native-notes deploy/backend -- python -c "
    import redis
    import json
    r = redis.Redis(host='redis-service', port=6379, password='my-secure-redis-password', decode_responses=True)
    r.set('test:connection', json.dumps({'status': 'working'}))
    print(r.get('test:connection'))
    r.delete('test:connection')
    "
    ```

    Expected Result: 
    
    **{"status": "working"}**

3. Check the app health on the terminal or browser

   `curl http://localhost:3000/health` 
   
   `curl http://localhost:3000/debug/config`
   
   You should see `redis_connected: True`. If `false`, your data would not persist. Try to fix it.
   
   

4. Post messages

    ```
    curl -X POST http://localhost:3000/api/notes -H "Content-Type: application/json" -d '{"title":"Week 4","content":"Yay! I am working with ConfigMaps, Secrets and Storage!"}'

    curl -X POST http://localhost:3000/api/notes -H "Content-Type: application/json" -d '{"title":"Persistence Test","content":"If you see me after restart, then your storage worked!"}'
    ```


5. View your notes after backend restarts

    `curl http://localhost:3000/api/notes`



## Verify

Run the verification script `./verify-week4.sh`

If your verification score is 100%, you are good to go!

If not, read the report and rectify the error(s).

If you are stucked after several trials, ask for help in the group.
