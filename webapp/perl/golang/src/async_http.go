package main

import (
	"encoding/json"
	"log"
	"io/ioutil"
	"runtime"
	"net"
	"net/http"
	"crypto/tls"
	"sync"
	"time"
)

type Data struct {
	Service    string                 `json:"service"`
	Value	   map[string]interface{} `json:"data"`
	CacheKey   string                 `json:"cache_key"`
	Expiration int64                  `json:"expiration"`
}

type Req struct {
	Service    string            `json:"service"`
	Endpoint   string            `json:"endpoint"`
	Headers	   map[string]string `json:"headers"`
	CacheKey   string            `json:"cache_key"`
	Expiration int64             `json:"expiration"`
}

var client = &http.Client{
	Transport: &http.Transport{
		Proxy: http.ProxyFromEnvironment,
		Dial: (&net.Dialer{
			Timeout:   30 * time.Second,
			KeepAlive: 30 * time.Second,
		}).Dial,
		MaxIdleConnsPerHost: 256,
		TLSClientConfig: &tls.Config{
			InsecureSkipVerify: true,
		},
		TLSHandshakeTimeout: 10 * time.Second,
	},
}

func main() {
	runtime.GOMAXPROCS(runtime.NumCPU())
	http.HandleFunc("/", handler)
	http.ListenAndServe(":8083", nil)
}

func handler(w http.ResponseWriter, r *http.Request) {
	var requests []Req
	body, _ := ioutil.ReadAll(r.Body)
	log.Printf("body: %s", body)
	json.Unmarshal(body, &requests)

	reciever := parallelReq(requests)
	data := make([]Data, 0, len(requests))
	for res := range reciever {
		data = append(data, res)
	}

	json, err := json.Marshal(data)
	if err != nil {
		log.Printf("[invalid json] url: %s", r.URL.Path)
		panic(err)
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(json)
	log.Printf("[done] json: %s", json)
}

func parallelReq(requests []Req) <-chan Data {
	wg := &sync.WaitGroup{}
	reciever := make(chan Data, len(requests))

	for _, request := range requests {
		service    := request.Service
		endpoint   := request.Endpoint
		cacheKey   := request.CacheKey
		expiration := request.Expiration

		req, err := http.NewRequest("GET", endpoint, nil)
		if err != nil {
			log.Printf("[failed to create request] url: %s", request.Endpoint)
			panic(err)
		}
		for key, value := range request.Headers {
			req.Header.Set(key, value)
		}

		wg.Add(1)
		go func() {
			data := doRequest(req)
			reciever <- Data{
				Service:    service,
				Value:      data,
				CacheKey:   cacheKey,
				Expiration: expiration,
			}
			wg.Done()
		}()
	}

	go func() {
		wg.Wait()
		close(reciever)
	}()

	return reciever
}

func doRequest(req *http.Request) map[string]interface{} {
	log.Printf("[start] url: %s", req.URL.Path)

	res, err := client.Do(req)
	if err != nil {
		log.Printf("[end] url: %s", req.URL.Path)
		panic(err)
	}
	defer res.Body.Close()

	log.Printf("[end] url: %s [%d] len: %d", req.URL.Path, res.StatusCode, res.ContentLength)
	if res.StatusCode == 429 {
		time.Sleep(1 * time.Microsecond)
		return doRequest(req)
	}

	var data map[string]interface{}
	d := json.NewDecoder(res.Body)
	d.UseNumber()
	if err := d.Decode(&data); err != nil {
		log.Printf("[invalid json] url: %s", req.URL.Path)
		panic(err)
	}

	return data
}
