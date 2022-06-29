# Grifter Docker Setup

To setup Grifter to run in a Docker container, follow these steps:

1. Build the docker image:
Assuming you start in the root of this repository
```bash
cd docker
docker build -t grifter:latest .
```
2. Edit the docker-compose.yml and replace the placeholders (paths on your host and external port of the container)


3. Run the container:
```bash
docker-compose up -d
```

4. Done! You should now be able to access Grifter in your browser under the port you set in the docker-compose.yml