FROM zengyiheng/hugo as builder

COPY ./ /data
WORKDIR /data
RUN hugo


FROM nginx:1.15-alpine
COPY --from=builder /data/public /public
RUN mv /public/* /usr/share/nginx/html/
