# --- builder ---
FROM ruby:4.0.4-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libssl-dev zlib1g-dev libyaml-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV BUNDLE_WITHOUT=development:test \
    BUNDLE_DEPLOYMENT=1

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4

COPY . .

# --- runtime ---
FROM ruby:4.0.4-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 zlib1g curl && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd -r rails && useradd -r -g rails -u 1000 rails

WORKDIR /app

COPY --chown=rails:rails --from=builder /app /app

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT=development:test

USER rails

EXPOSE 3000
