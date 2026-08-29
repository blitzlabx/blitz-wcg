FROM ruby:3.2-slim

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends build-essential libffi-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock* ./
RUN bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

COPY . .

RUN mkdir -p data logs data/cache && \
    chmod +x bin/bot

ENV RACK_ENV=production
ENV DATA_DIR=/app/data
ENV PORT=3000

EXPOSE 3000

CMD ["bundle", "exec", "ruby", "bin/bot"]
