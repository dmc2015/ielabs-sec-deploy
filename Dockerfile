# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.3.6

# Get current digest
# docker pull ruby:3.3.6-slim && docker inspect --format='{{index.RepoDigests 0}}'
# ruby:3.3.6-slim
FROM registry.docker.com/library/ruby@sha256:b210597cc7d05e19edf9c8e7935dcf1554886905dcdad0475cfe63a654147f7a as base


# Update RubyGems and install correct bundler version
RUN gem update --system 3.3.22 && \
    gem install bundler:2.5.23

# Rails app lives here
WORKDIR /rails

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

# Throw-away build stage to reduce size of final image
FROM base as build

# Install packages needed to build gems and node modules
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential curl git libpq-dev libvips libffi-dev node-gyp pkg-config python-is-python3

# Install JavaScript dependencies
ARG NODE_VERSION=23.9.0
ARG YARN_VERSION=1.22.19
ENV PATH=/usr/local/node/bin:$PATH
RUN curl -sL https://github.com/nodenv/node-build/archive/master.tar.gz | tar xz -C /tmp/ && \
    /tmp/node-build-master/bin/node-build "${NODE_VERSION}" /usr/local/node && \
    npm install -g yarn@$YARN_VERSION && \
    rm -rf /tmp/node-build-master

# Install application gems
COPY Gemfile Gemfile.lock ./

# Install gems WITHOUT the --without flag first (to get bootsnap)
RUN bundle _2.5.23_ install --without="" && \
    bundle exec bootsnap precompile --gemfile && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Install node modules
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Final stage for app image
FROM base


# HEALTHCHECK — a command Docker runs periodically inside the container to decide if it's
#  healthy. Your line runs curl http://localhost:3000/up every 30s; if it fails 3 times in
#  a row, Docker marks the container unhealthy. Shows up in docker ps status.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -fsS http://localhost:3000/up || exit 1

# LABEL — metadata attached to the image. Just key=value pairs, doesn't affect runtime.
#  The org.opencontainers.image.* names are a standard (OCI) that registries like GHCR read
#   to show "source repo," "description," "license" on the image's web page. Useful so
#  hiring managers clicking your GHCR image see it links back to the sec-deploy repo.
LABEL org.opencontainers.image.source="https://github.com/dmc2015/ielabs-sec-deploy" \
  org.opencontainers.image.description="IELabs Rails app - secure build" \
  org.opencontainers.image.licenses="MIT"

# Install packages needed for deployment (including libffi for runtime)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libvips libffi8 postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy built artifacts: gems, application
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security
RUN useradd rails --uid 1001 --create-home --shell /usr/sbin/nologin && \
    chown -R rails:rails db log storage tmp
USER rails:rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 3000
CMD ["./bin/rails", "server"]
