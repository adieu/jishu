FROM zengyiheng/hugo:v0.72.0-git as builder

COPY ./ /data
WORKDIR /data
RUN git submodule init
RUN git submodule update
RUN hugo



FROM nginx:1.15-alpine
COPY --from=builder /data/public /public
RUN mv /public/* /usr/share/nginx/html/
