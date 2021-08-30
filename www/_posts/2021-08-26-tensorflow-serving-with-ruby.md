---
layout: post
title: Tensorflow Serving with Ruby
keywords: grpc, tensorflow, machine learning
---

The [Tensorflow framework](https://www.tensorflow.org/) is the most used framework when it comes to develop, train and deploy Machine Learning models. It ships with first class API support for `python` and `C++`, the former being a favourite of most data scientists, which explains the pervasiveness of `python` in virtually all of the companies relying on ML for their products.

When it comes to deploying ML-based web services, there are two options. The first one is to develop a `python` web service, using something like `flask` or `django`, add `tensorflow` as a dependency, and run the model from within it. This approach is straightforward, but it comes with its own set of problems: rolling out model upgrades has to be done for each application using it, and even ensuring that the same `tensorflow` library version is used everywhere tends to be difficult, it being a pretty heavy dependency, which often conflicts with other libraries in the python ecosystem, and is frequently the subject of CVEs. All of this introduces risk in the long run.

The other approach is to deploy the models using [Tensorflow Serving](https://www.tensorflow.org/tfx/guide/serving) ([pytorch has something similar, torchserve](https://pytorch.org/serve/inference_api.html)). In short, it exposes the execution of the ML models over the network "as a service". It supports model versioning, and can be interfaced with via gRPC or REST API, which solves the main integration issues from the previously described approach. It thus allows to compartimentalize the risks from the other approach, while also enabling the possibilitiy of throwing dedicated hardware at it.

It also allows you to ditch `python` when building applications.

### Research and Development

Now, I'm not a `python` hater. It's an accessible programming language. It shares a lot of benefits and drawbacks with `ruby`. But by the time a company decides to invest in ML to improve their product, the tech team might already be heavily familiar with a different tech stack. Maybe it's `ruby`, maybe `java`, maybe `go`. It's unreasonable to replace all of them with `python` experts. It's possible to ask them to use a bit of `python`, but that comes at the cost of learning a new stack (thereby decreasing quality of delivery) and alienating the employees (thereby increasing turnover).

It's also unreasonable to ask from the new data science team to not use their preferred `python` tech stack. It's an ML *lingua franca*, and there's way more years of investment and resources poured into libraries like [numpy](https://numpy.org/) or [scikit](https://scikit-learn.org/stable/index.html). And although there's definitely value in improving the state of ML in your preferred languages (shout out at the [SciRuby](http://sciruby.com/) folks) and diminish the overall industry dependency on `python`, that should not come at the cost of decreasing the quality of your product.

Therefore, `tensorflow-serving` allows the tech team to focus on developing and shipping the best possible product, and the research team to focus on developing the best possible  models. Everyone's productive and happy.

### Tensorflow Serving with JSON

As stated above, `tensorflow serving` services are exposed using `gRPC` and REST APIs. IF you didn't use `gRPC` before, you'll probably privilege the latter; you've done HTTP JSON clients for other APIs before, how hard can it be creating an HTTP client for it?

While certainly possible, going this route will come at a cost; besides ensuring that the HTTP layer works reliably, using persistent connections, timeouts, etc, there's the cost of JSON.

`tensorflow` (and other ML frameworks in general) makes heavy use of "tensors", multi-dimensional same-type arrays (vectors, matrixes...), describing, for example, the coordinates of a face recognized in an image. These tensors are represented in memory as contiguous array objects, and can be therefore easily serialized into a bytestream. Libraries like `numpy` (or `numo` in ruby) take advantage of this memory layout to provide high-performance mathematical and logical operations.

JSON is UTF-8, and can't encode byte streams; in order to send and receive byte streams using the REST API interface, you'll have to convert to and from base 64 notation. This means that, besides the CPU usage overhead for these operations, you should expect a ~33% increase in the transmitted payload.

The `tensorflow-serving` REST API proxies to the `gRPC` layer, so there's also this extra level of indirection to account for.

`gRPC` doesn't suffer from these drawbacks; on top of `HTTP/2`, it not only improves connnectivity, it also solves multiplexing and streaming; using `protobufs`, it has a typed message serialization protocol which supports byte streams.

How can it be used in `ruby` then?

### Tensorflow Serving with Protobufs

Tensorflow Serving calls are performed using a standardized set of common protobufs, which `.proto` definitions can be found both in the [tensorflow](https://github.com/tensorflow/tensorflow) repo, as well as in the [tensorflow-serving](https://github.com/tensorflow/serving) repo. The most important for our case are declared under [prediction_service.proto](https://github.com/tensorflow/serving/blob/master/tensorflow_serving/apis/prediction_service.proto), which defines request and response protobufs declaring which model version to run, and how input and output tensors are laid out.

Both libraries above already package the `python` protobufs. To use them in `ruby`, you have to compile them yourself using the [protobuf](https://github.com/ruby-protobuf/protobuf) gem. For this particular case, compiling can be a pretty involved process, which looks like this:

```bash
# gem install grpc-tools

TF_VERSION="2.5.0"
TF_SERVING_VERSION="2.5.1"
PROTO_PATH=path/to/protos
set -o pipefail

curl -L -o tensorflow.zip https://github.com/tensorflow/tensorflow/archive/v$TF_VERSION.zip
unzip tensorflow.zip && rm tensorflow.zip
mv tensorflow-$TF_VERSION ${PROTO_PATH}/tensorflow

curl -L -o tf-serving.zip https://github.com/tensorflow/serving/archive/$TF_SERVING_VERSION.zip
unzip tf-serving.zip && rm tf-serving.zip
mv serving-$TF_SERVING_VERSION/tensorflow_serving ${PROTO_PATH}/tensorflow


TF_SERVING_PROTO=${PROTO_PATH}/ruby
mkdir ${TF_SERVING_PROTO}

grpc_tools_ruby_protoc \
    -I ${PROTO_PATH}/tensorflow/tensorflow/core/framework/*.proto \
    --ruby_out=${TF_SERVING_PROTO} \
    --grpc_out=${TF_SERVING_PROTO} \
    --proto_path=${PROTO_PATH}/tensorflow

grpc_tools_ruby_protoc \
    -I ${PROTO_PATH}/tensorflow/tensorflow/core/example/*.proto \
    --ruby_out=${TF_SERVING_PROTO} \
    --grpc_out=${TF_SERVING_PROTO} \
    --proto_path=${PROTO_PATH}/tensorflow

grpc_tools_ruby_protoc \
    -I ${PROTO_PATH}/tensorflow/tensorflow/core/protobuf/*.proto \
    --ruby_out=${TF_SERVING_PROTO} \
    --grpc_out=${TF_SERVING_PROTO} \
    --proto_path=${PROTO_PATH}/tensorflow

grpc_tools_ruby_protoc \
    ${PROTO_PATH}/tensorflow/tensorflow_serving/apis/*.proto \
    --ruby_out=${TF_SERVING_PROTO} \
    --grpc_out=${TF_SERVING_PROTO} \
    --proto_path=${PROTO_PATH}/tensorflow

ls $TF_SERVING_PROTO
```

**NOTE**: There's also the [tensorflow-serving-client](https://github.com/nubbel/tensorflow_serving_client-ruby), which already ships with the necessary `ruby` protobufs, however there hasn't been any updates in more than 5 years, so I can't attest to its state of maintenance. So if you want to use this in production, make sure you generate ruby stubs from the latest version of definitons.

Once the protobufs are available, creating a `PredictRequest` is simple. Here's how you'd encode a request to a model called `mnist`, taking a 784-wide float array as input:

```ruby
require "path/to/protos/ruby/tensorflow_serving/apis/prediction_service_pb"

tensor = [0.0] * 784

request = Tensorflow::Serving::PredictRequest.new
request.model_spec = Tensorflow::Serving::ModelSpec.new name: 'mnist'
request.inputs['images'] = Tensorflow::TensorProto.new(
  float_val: tensor,
  tensor_shape: Tensorflow::TensorShapeProto.new(
    dim: [
      Tensorflow::TensorShapeProto::Dim.new(size: 1),
      Tensorflow::TensorShapeProto::Dim.new(size: 784)
    ]
  ),
  dtype: Tensorflow::DataType::DT_FLOAT
)
```

**NOTE**: `tensorflow` python API ships with a very useful function called [make_tensor_proto](https://www.tensorflow.org/api_docs/python/tf/make_tensor_proto), which could do the above as a "one-liner". While it's certainly possible to code a similar function in `ruby`, it's a pretty involved process which is beyond the scope of this post.

As an example, this one is easy to grasp. However, we'll have to deal with much larger tensors in production, which is going to get heavier and slower to deal with using `ruby` arrays.

### Tensorflow Serving with Numo and GRPC

In `python`, the standard for using n-dimensional arrays is [numpy](https://numpy.org/). `ruby` has a similar library called [numo](https://github.com/ruby-numo/numo).

It aims at providing the same APIs as `numpy`, which is mostly an aspirational goal, as keeping up with `numpy` is hard (progress can be tracked [here](https://github.com/ruby-numo/numo-narray/wiki/Numo-vs-numpy)).

A lot can be done already though, such as [image processing](https://github.com/yoshoku/magro). If our model requires an image, this is how it can be done in `python`:

```python
# using numpy
import grpc
import numpy as np
from PIL import Image
import tensorflow as tf
from tensorflow_serving.apis import predict_pb2, prediction_service_pb2_grpc

img = Image.open('test-image.png')
tensor = np.asarray(img)
tensor.shape #=> [512,512,3]


request = predict_pb2.PredictRequest()
request.model_spec.name = "mnist"
request.inputs['images'].CopyFrom(tf.make_tensor_proto(tensor))


stub = prediction_service_pb2_grpc.PredictionServiceStub(grpc.insecure_channel("localhost:9000"))
response = stub.Predict(request)
print(response.outputs)
```

And this is the equivalent `ruby` code:

```ruby
require "grpc"
require "path/to/protos/ruby/tensorflow_serving/apis/prediction_service_pb"

# magro reads images to numo arrays
require "magro"


def build_predict_request(tensor)
  request = Tensorflow::Serving::PredictRequest.new
  request.model_spec = Tensorflow::Serving::ModelSpec.new name: 'mnist'
  request.inputs['images'] = Tensorflow::TensorProto.new(
    binary_val: tensor.to_binary,
    tensor_shape: Tensorflow::TensorShapeProto.new(
      dim: tensor.shape.map{ |size| Tensorflow::TensorShapeProto::Dim.new(size: size) }
    ),
    dtype: Tensorflow::DataType::DT_UINT8
  )
end

tensor = Magro::IO.imread("test-image.png")
tensor.shape #=> [512,512,3]

# using tensorflow-serving-client example
stub = Tensorflow::Serving::PredictionService::Stub.new('localhost:9000', :this_channel_is_insecure)
res = stub.predict( build_predict_request(tensor) )
puts res.outputs # returns PredictResponses
```

That's it!

### GRPC over HTTPX

[httpx ships with a grpc plugin](https://honeyryderchuck.gitlab.io/httpx/wiki/GRPC). This being a blog mostly about `httpx`, it's only fitting I show how to do the above using it :) .

```ruby
require "httpx"
require "magro"
require "path/to/protos/ruby/tensorflow_serving/apis/prediction_service_pb"

# ... same as above ...

stub = HTTPX.plugin(:grpc).build_stub("localhost:9000", service: Tensorflow::Serving::PredictionService)
res = stub.predict( build_predict_request(tensor) )
puts res.outputs # returns PredictResponses
```

### Conclusion

Hopefully you've gained enough interest about some `ruby` ML toolchain to investigate further. Who knows, maybe you can teach your researcher friends about. However, the ML industry won't move away from `python` soon, so at least you know some more about how you can still use `ruby` to build your services, while interfacing remotely with ML models, running on dedicated hardware, using the gRPC protocol.